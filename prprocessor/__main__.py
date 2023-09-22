# pylint: disable=missing-module-docstring,missing-class-docstring,missing-function-docstring

import asyncio
import logging
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import AsyncGenerator, Collection, Generator, Iterable, Mapping, Optional

import yaml
from octomachinery.app.routing import process_event_actions
from octomachinery.app.routing.decorators import process_webhook_payload
from octomachinery.app.runtime.context import RUNTIME_CONTEXT
from octomachinery.app.server.runner import run as run_app
from pkg_resources import resource_filename
from redminelib.resources import Issue, Project

from prprocessor import get_version_prefix_from_branch
from prprocessor.redmine import (Field, Status, get_issues, get_latest_open_version, get_redmine,
                                 set_fixed_in_version, verify_issues, IssueValidation)


COMMIT_VALID_SUMMARY_REGEX = re.compile(
    r'\A(?P<action>fixes|refs) (?P<issues>#(\d+)(, ?#(\d+))*)(:| -) .*\Z',
    re.IGNORECASE,
)
COMMIT_ISSUES_REGEX = re.compile(r'#(\d+)')
CHECK_NAME = 'Redmine issues'
WHITELISTED_ORGANIZATIONS = ('theforeman', 'Katello')


class Label(Enum):
    WAITING_ON_CONTRIBUTOR = 'Waiting on contributor'
    NEEDS_RE_REVIEW = 'Needs re-review'
    NOT_YET_REVIEWED = 'Not yet reviewed'
    STABLE_BRANCH = 'Stable branch'

    # Only applies to foreman-packaging
    DEB = 'DEB'
    RPM = 'RPM'

    @staticmethod
    def load_labels(labels: Iterable[str]) -> set['Label']:
        result: set[Label] = set()

        for label in labels:
            try:
                result.add(Label(label))
            except ValueError:
                pass

        return result


class UnconfiguredRepository(Exception):
    pass


@dataclass
class Commit:
    sha: str
    message: str
    fixes: set = field(default_factory=set)
    refs: set = field(default_factory=set)

    @property
    def subject(self):
        return self.message.splitlines()[0]


@dataclass
class Config:
    project: Optional[str] = None
    required: bool = False
    refs: set = field(default_factory=set)
    version_prefix: Optional[str] = None
    apply_labels: bool = True


# This should be handled cleaner
with open(resource_filename(__name__, 'config/repos.yaml')) as config_fp:
    CONFIG = {
        repo: Config(project=config.get('redmine'), required=config.get('redmine_required', False),
                     refs=set(config.get('refs', [])),
                     version_prefix=config.get('redmine_version_prefix'))
        for repo, config in yaml.safe_load(config_fp).items()
    }

with open(resource_filename(__name__, 'config/users.yaml')) as users_fp:
    USERS = yaml.safe_load(users_fp)


logger = logging.getLogger('prprocessor')  # pylint: disable=invalid-name


def get_config(repository: str) -> Config:
    try:
        return CONFIG[repository]
    except KeyError:
        user, _ = repository.split('/', 1)
        if user not in WHITELISTED_ORGANIZATIONS:
            logger.info('The repository %s is unconfigured and user %s not whitelisted',
                        repository, user)
            raise UnconfiguredRepository(f'The repository {repository} is unconfigured')
        return Config(apply_labels=False)


def pr_is_cherry_pick(pull_request: Mapping) -> bool:
    return pull_request['title'].startswith(('CP', '[CP]', 'Cherry picks for '))


def summarize(summary: Mapping[str, Iterable], show_headers: bool) -> Generator[str, None, None]:
    for header, lines in summary.items():
        if lines:
            if show_headers:
                yield f'### {header}'
            for line in lines:
                yield f'* {line}'


async def update_pr_labels(pull_request: Mapping, labels_to_add: Iterable[Label],
                           labels_to_remove: Iterable[Label]) -> None:
    github_api = RUNTIME_CONTEXT.app_installation_client

    tasks = []

    repository = pull_request['base']['repo']['full_name']

    # TODO: pull_request['labels_url']
    # https://github.com/orgs/community/discussions/66499
    url = f'{pull_request["issue_url"]}/labels{{/name}}'

    if labels_to_add:
        logger.info('%s PR #%s: adding labels: %r', repository, pull_request['number'], labels_to_add)
        data = [label.value for label in labels_to_add]
        tasks.append(github_api.post(url, data=data))

    for label in labels_to_remove:
        logger.info('%s PR #%s: removing label: %s', repository, pull_request['number'], label)
        tasks.append(github_api.delete(url, url_vars={'name': label.value}))

    if tasks:
        await asyncio.gather(*tasks)


async def get_commits_from_pull_request(pull_request: Mapping) -> AsyncGenerator[Commit, None]:
    github_api = RUNTIME_CONTEXT.app_installation_client
    items = await github_api.getitem(pull_request['commits_url'])
    for item in items:
        commit = Commit(item['sha'], item['commit']['message'])

        match = COMMIT_VALID_SUMMARY_REGEX.match(commit.subject)
        if match:
            action = getattr(commit, match.group('action').lower())
            for issue in COMMIT_ISSUES_REGEX.findall(match.group('issues')):
                action.add(int(issue))

        yield commit


async def set_check_in_progress(pull_request: Mapping, check_run=None):
    github_api = RUNTIME_CONTEXT.app_installation_client

    data = {
        'name': CHECK_NAME,
        'head_branch': pull_request['head']['ref'],
        'head_sha': pull_request['head']['sha'],
        'status': 'in_progress',
        'started_at': datetime.now(tz=timezone.utc).isoformat(),
    }

    if check_run:
        if check_run['status'] != 'in_progress':
            await github_api.patch(check_run['url'], data=data, preview_api_version='antiope')
    else:
        url = f'{pull_request["base"]["repo"]["url"]}/check-runs'
        check_run = await github_api.post(url, data=data, preview_api_version='antiope')

    return check_run


def format_invalid_commit_messages(commits: Iterable[Commit]) -> Collection[str]:
    return [f"{commit.sha} must be in the format `fixes #redmine - brief description`"
            for commit in commits]


def format_redmine_issues(issues: Iterable[Issue]) -> Collection[str]:
    return [f"[#{issue.id}: {issue.subject}]({issue.url})"
            for issue in sorted(issues, key=lambda issue: issue.id)]


def format_details(invalid_issues: Iterable[Issue], correct_project: Project) -> str:
    text = []
    for issue in invalid_issues:
        # Would be nice to get the new issue URL via a property
        text.append(f"""### [#{issue.id}: {issue.subject}]({issue.url})

* check [#{issue.id}]({issue.url}) is the intended issue
* move [ticket #{issue.id}]({issue.url}) from {issue.project.name} to the {correct_project.name} project
* or file a new ticket in the [{correct_project.name} project]({correct_project.url}/issues/new)
""")

    return '\n'.join(text)


async def get_issues_from_pr(pull_request: Mapping) -> tuple[IssueValidation, Collection]:
    config = get_config(pull_request['base']['repo']['full_name'])

    issue_ids = set()
    invalid_commits = []

    async for commit in get_commits_from_pull_request(pull_request):
        issue_ids.update(commit.fixes)
        issue_ids.update(commit.refs)
        if config.required and not commit.fixes and not commit.refs:
            invalid_commits.append(commit)

    return verify_issues(config, issue_ids), invalid_commits


async def run_pull_request_check(pull_request: Mapping, check_run=None) -> bool:
    github_api = RUNTIME_CONTEXT.app_installation_client

    check_run = await set_check_in_progress(pull_request, check_run)

    # We're very pessimistic
    conclusion = 'failure'

    attempts = 3

    try:
        for attempt in range(1, attempts + 1):
            try:
                issue_results, invalid_commits = await get_issues_from_pr(pull_request)
                break
            except:  # pylint: disable=bare-except
                if attempt == attempts:
                    raise
                logger.exception('Failure during validation of PR (attempt %s)', attempt)
                await asyncio.sleep(attempt)
    except UnconfiguredRepository:
        output = {
            'title': 'Unknown repository',
            'summary': 'Contact us via [Discourse](https://community.theforeman.org]',
        }
    except:  # pylint: disable=bare-except
        logger.exception('Failure during validation of PR')
        output = {
            'title': 'Internal error while testing',
            'summary': 'Please retry later',
        }
    else:
        try:
            await update_redmine_on_issues(pull_request, issue_results.valid_issues)
        except:  # pylint: disable=bare-except
            logger.exception('Failed to update Redmine issues')

        summary: dict[str, Collection] = {
            'Invalid commits': format_invalid_commit_messages(invalid_commits),
            'Invalid project': format_redmine_issues(issue_results.invalid_project_issues),
            'Issues not found in redmine': issue_results.missing_issue_ids,
            'Valid issues': format_redmine_issues(issue_results.valid_issues),
        }

        non_empty = [title for title, lines in summary.items() if lines]
        multiple_sections = len(non_empty) != 1
        if not any(True for header in non_empty if header != 'Valid issues'):
            conclusion = 'success'

        output = {
            'title': 'Redmine Issue Report' if multiple_sections else non_empty[0],
            'summary': '\n'.join(summarize(summary, multiple_sections)),
            'text': format_details(issue_results.invalid_project_issues, issue_results.project),
        }

        # > For 'properties/text', nil is not a string.
        # That means it's not possible to delete the text by setting None, but
        # sometimes we can avoid setting it
        if not output['text'] and not check_run['output'].get('text'):
            del output['text']

    await github_api.patch(
        check_run['url'],
        preview_api_version='antiope',
        data={
            'status': 'completed',
            'head_branch': pull_request['head']['ref'],
            'head_sha': pull_request['head']['sha'],
            'completed_at': datetime.now(tz=timezone.utc).isoformat(),
            'conclusion': conclusion,
            'output': output,
        },
    )

    return conclusion == 'success'


async def update_redmine_on_issues(pull_request: Mapping, issues: Iterable[Issue]) -> None:
    pr_url = pull_request['html_url']
    assignee = USERS.get(pull_request['user']['login'])

    for issue in issues:
        status = Status(issue.status.id)

        if not status.is_rejected():
            updates = {}
            # TODO: rewrite this
            #if issue.backlog or issue.recycle_bin or not issue.fixed_version_id:
            #    triaged_field = issue.custom_fields.get(Field.TRIAGED)
            #    if triaged_field.value is True:  # TODO does the API return a boolean?
            #        updates['custom_fields'] = [{'id': triaged_field.id, 'value': False}]

            #    updates['fixed_version_id'] = None

            if not pr_is_cherry_pick(pull_request):
                pr_field = issue.custom_fields.get(Field.PULL_REQUEST)
                if pr_url not in pr_field.value:
                    if 'custom_fields' not in updates:
                        updates['custom_fields'] = []
                    new_value = pr_field.value + [pr_url]
                    updates['custom_fields'].append({'id': pr_field.id, 'value': new_value})

            if assignee and not hasattr(issue, 'assigned_to'):
                updates['assigned_to_id'] = assignee

            if not (status.is_closed() or status == Status.READY_FOR_TESTING):
                updates['status_id'] = Status.READY_FOR_TESTING.value

            if updates:
                logger.info('Updating issue %s: %s', issue.id, updates)
                issue.save(**updates)
            else:
                logger.debug('Redmine issue %s already in sync', issue.id)


@process_event_actions('pull_request', {'opened', 'ready_for_review', 'reopened', 'synchronize'})
@process_webhook_payload
async def on_pr_modified(*, action: str, pull_request: Mapping, **_kw) -> None:
    commits_valid_style = await run_pull_request_check(pull_request)

    try:
        config = get_config(pull_request['base']['repo']['full_name'])
    except UnconfiguredRepository:
        return

    if not config.apply_labels:
        return

    labels_before = Label.load_labels(label['name'] for label in pull_request['labels'])
    labels = labels_before.copy()

    if action == 'opened':
        labels.add(Label.NOT_YET_REVIEWED)

    if action == 'synchronize' and Label.WAITING_ON_CONTRIBUTOR in labels:
        labels.discard(Label.WAITING_ON_CONTRIBUTOR)
        if Label.NOT_YET_REVIEWED not in labels:
            labels.add(Label.NEEDS_RE_REVIEW)

    if not commits_valid_style:
        labels.add(Label.WAITING_ON_CONTRIBUTOR)

    # TODO: handle None value (result is being calculated by GH) and resubmit later?
    if pull_request['mergeable'] is False:
        # TODO: post message the PR has a conflict?
        labels.discard(Label.NEEDS_RE_REVIEW)
        labels.discard(Label.NOT_YET_REVIEWED)
        labels.add(Label.WAITING_ON_CONTRIBUTOR)

    labels_to_add = labels - labels_before
    labels_to_remove = labels_before - labels

    target_branch = pull_request['base']['ref']
    if target_branch.endswith('-stable') or target_branch.startswith('KATELLO-'):
        labels.add(Label.STABLE_BRANCH)

    if target_branch.startswith('deb/'):
        labels.add(Label.DEB)
    elif target_branch.startswith('rpm/'):
        labels.add(Label.RPM)

    await update_pr_labels(pull_request, labels_to_add, labels_to_remove)


@process_event_actions('pull_request_review', {'submitted'})
@process_webhook_payload
async def on_pr_review_assign_labels(*, pull_request: Mapping, review: Mapping, **_kw) -> None:
    labels_before = Label.load_labels(label['name'] for label in pull_request['labels'])
    labels = labels_before.copy()

    # TODO: look at review['author_association'] to see if the review has permissions?

    state = review['state']
    if state in ('rejected', 'changes_requested'):
        labels.discard(Label.NOT_YET_REVIEWED)
        labels.discard(Label.NEEDS_RE_REVIEW)
        labels.add(Label.WAITING_ON_CONTRIBUTOR)
    elif state == 'approved':
        labels.discard(Label.NOT_YET_REVIEWED)
        labels.discard(Label.NEEDS_RE_REVIEW)

    labels_to_add = labels - labels_before
    labels_to_remove = labels_before - labels

    await update_pr_labels(pull_request, labels_to_add, labels_to_remove)


@process_event_actions('check_run', {'rerequested'})
@process_webhook_payload
async def on_check_run(*, check_run: Mapping, **_kw) -> None:
    github_api = RUNTIME_CONTEXT.app_installation_client

    if not check_run['pull_requests']:
        logger.warning('Received check_run without PRs')

    for pr_summary in check_run['pull_requests']:
        pull_request = await github_api.getitem(pr_summary['url'])
        await run_pull_request_check(pull_request, check_run)


@process_event_actions('check_suite', {'requested', 'rerequested'})
@process_webhook_payload
async def on_suite_run(*, check_suite: Mapping, **_kw) -> None:
    github_api = RUNTIME_CONTEXT.app_installation_client

    check_runs = await github_api.getitem(check_suite['check_runs_url'],
                                          preview_api_version='antiope')

    for check_run in check_runs['check_runs']:
        if check_run['name'] == CHECK_NAME:
            break
    else:
        check_run = None

    if not check_suite['pull_requests']:
        logger.warning('Received check_suite without PRs')

    for pr_summary in check_suite['pull_requests']:
        pull_request = await github_api.getitem(pr_summary['url'])
        await run_pull_request_check(pull_request, check_run)


@process_event_actions('pull_request', {'closed'})
@process_webhook_payload
async def on_pr_merge(*, pull_request: Mapping, **_kw) -> None:
    """
    Only acts on merged PRs to a master or develop branch. There is no handling for stable
    branches.

    If there's a configuration, all related issues that have a Fixes #xyz are gathered. All of
    those that have a matching project according to the configuration are considered. With that
    list, the Redmine project's latest version is determined. If there is one, all issues receive
    the fixed_in_version.
    """

    repository = pull_request['base']['repo']['full_name']
    try:
        config = get_config(repository)
    except UnconfiguredRepository:
        return

    if not config.project:
        logger.info('Repository for %s not found', repository)
        return

    issue_ids = set()
    async for commit in get_commits_from_pull_request(pull_request):
        issue_ids.update(commit.fixes)

    if issue_ids:
        redmine = get_redmine()
        project = redmine.project.get(config.project)

        if pull_request['merged']:
            target_branch = pull_request['base']['ref']
            version_prefix = get_version_prefix_from_branch(target_branch)
            if version_prefix is None:
                logger.info('Unable to set fixed in version for %s branch %s in PR %s',
                            repository, target_branch, pull_request['number'])
                return

            if config.version_prefix:
                version_prefix = f'{config.version_prefix}{version_prefix}'

            fixed_in_version = get_latest_open_version(project, version_prefix)

            if not fixed_in_version:
                logger.info('Unable to determine latest version for %s; prefix=%s', project.name,
                            version_prefix)
                return

            for issue in get_issues(redmine, issue_ids):
                if issue.project.id == project.id:
                    logger.info('Setting fixed in version for issue %s to %s', issue.id,
                                fixed_in_version.name)
                    set_fixed_in_version(issue, fixed_in_version)
        else:
            pr_url = pull_request['html_url']

            for issue in get_issues(redmine, issue_ids):
                pr_field = issue.custom_fields.get(Field.PULL_REQUEST)
                try:
                    new_value = pr_field.value.remove(pr_url)
                except ValueError:
                    logger.debug('Issue %s not linked to PR %s', issue.id, pr_url)
                else:
                    logger.info('Removing PR %s from issue %s', pr_url, issue.id)
                    issue.save(custom_fields=[{'id': pr_field.id, 'value': new_value}])


def run_prprocessor_app() -> None:
    run_app(
        name='prprocessor',
        version='0.1.0',
        url='https://github.com/apps/prprocessor',
    )


if __name__ == "__main__":
    run_prprocessor_app()
