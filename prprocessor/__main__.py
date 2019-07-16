import logging
import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import AsyncGenerator, Collection, Dict, Generator, Iterable, Mapping, Optional, Tuple

import yaml
from octomachinery.app.routing import process_event_actions
from octomachinery.app.routing.decorators import process_webhook_payload
from octomachinery.app.runtime.context import RUNTIME_CONTEXT
from octomachinery.app.server.runner import run as run_app
from pkg_resources import resource_filename
from redminelib.resources import Issue, Project

from prprocessor.redmine import (get_issues, get_latest_open_version, get_redmine,
                                 set_fixed_in_version, verify_issues)


COMMIT_VALID_SUMMARY_REGEX = re.compile(
    r'\A(?P<action>fixes|refs) (?P<issues>#(\d+)(, ?#(\d+))*)(:| -) .*\Z',
    re.IGNORECASE,
)
COMMIT_ISSUES_REGEX = re.compile(r'#(\d+)')
CHECK_NAME = 'Redmine issues'


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


# This should be handled cleaner
with open(resource_filename(__name__, 'config/repos.yaml')) as config_fp:
    CONFIG = {
        repo: Config(project=config.get('redmine'), required=config.get('redmine_required', False),
                     refs=set(config.get('refs', [])),
                     version_prefix=config.get('redmine_version_prefix'))
        for repo, config in yaml.safe_load(config_fp).items()
    }


logger = logging.getLogger('prprocessor')  # pylint: disable=invalid-name


def get_config(repository: str) -> Config:
    try:
        return CONFIG[repository]
    except KeyError:
        return Config()


def summarize(summary: Mapping[str, Iterable]) -> Generator[str, None, None]:
    show_headers = len(summary) > 1
    for header, lines in summary.items():
        if show_headers:
            yield f'### {header}'
        for line in lines:
            yield f'* {line}'


async def get_commits_from_pull_request(pull_request) -> AsyncGenerator[Commit, None]:
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


async def set_check_in_progress(pull_request, check_run=None):
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


async def verify_pull_request(pull_request) -> Tuple[Mapping[str, Collection], str]:
    config = get_config(pull_request['base']['repo']['full_name'])

    issue_ids = set()
    invalid_commits = []

    async for commit in get_commits_from_pull_request(pull_request):
        issue_ids.update(commit.fixes)
        issue_ids.update(commit.refs)
        if config.required and not commit.fixes and not commit.refs:
            invalid_commits.append(commit)

    issue_results = verify_issues(config, issue_ids)

    summary: Dict[str, Collection] = {
        'Invalid commits': format_invalid_commit_messages(invalid_commits),
        'Invalid project': format_redmine_issues(issue_results.invalid_project_issues),
        'Issues not found in redmine': issue_results.missing_issue_ids,
        'Valid issues': format_redmine_issues(issue_results.valid_issues),
    }

    details = format_details(issue_results.invalid_project_issues, issue_results.project)

    return summary, details


async def run_pull_request_check(pull_request, check_run=None) -> None:
    github_api = RUNTIME_CONTEXT.app_installation_client

    check_run = await set_check_in_progress(pull_request, check_run)

    # We're very pessimistic
    conclusion = 'failure'

    try:
        status, text = await verify_pull_request(pull_request)
    except:  # pylint: disable=bare-except
        logger.exception('Failure during validation of PR')
        output = {
            'title': 'Internal error while testing',
            'summary': 'Please retry later',
        }
    else:
        summary = {header: lines for header, lines in status.items() if lines}

        if len(summary) == 1:
            title = next(iter(summary.keys()))
        else:
            title = 'Redmine Issue Report'

        if not any(lines for header, lines in summary.items() if header != 'Valid issues'):
            conclusion = 'success'

        output = {
            'title': title,
            'summary': '\n'.join(summarize(summary)),
            'text': text,
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


@process_event_actions('pull_request', {'opened', 'ready_for_review', 'reopened', 'synchronize'})
@process_webhook_payload
async def on_pr_modified(*, pull_request: Mapping, **other) -> None:  # pylint: disable=unused-argument
    await run_pull_request_check(pull_request)


@process_event_actions('check_run', {'rerequested'})
@process_webhook_payload
async def on_check_run(*, check_run: Mapping, **other) -> None:  # pylint: disable=unused-argument
    github_api = RUNTIME_CONTEXT.app_installation_client

    if not check_run['pull_requests']:
        logger.warning('Received check_run without PRs')

    for pr_summary in check_run['pull_requests']:
        pull_request = await github_api.getitem(pr_summary['url'])
        await run_pull_request_check(pull_request, check_run)


@process_event_actions('check_suite', {'requested', 'rerequested'})
@process_webhook_payload
async def on_suite_run(*, check_suite: Mapping, **other) -> None:  # pylint: disable=unused-argument
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
async def on_pr_merge(*, pull_request: Mapping, **other) -> None:  # pylint: disable=unused-argument
    """
    Only acts on merged PRs to a master or develop branch. There is no handling for stable
    branches.

    If there's a configuration, all related issues that have a Fixes #xyz are gathered. All of
    those that have a matching project according to the configuration are considered. With that
    list, the Redmine project's latest version is determined. If there is one, all issues receive
    the fixed_in_version.
    """

    if not pull_request['merged']:
        logger.debug('Pull request %s was closed, not merged', pull_request['number'])
        return

    repository = pull_request['base']['repo']['full_name']
    target_branch = pull_request['base']['ref']
    if target_branch not in ('master', 'develop'):
        logger.info('Unable to set fixed in version for %s branch %s in PR %s',
                    repository, target_branch, pull_request['number'])
        return

    config = get_config(repository)
    if not config.project:
        logger.info('Repository for %s not found', repository)
        return

    issue_ids = set()
    async for commit in get_commits_from_pull_request(pull_request):
        issue_ids.update(commit.fixes)

    if issue_ids:
        redmine = get_redmine()
        project = redmine.project.get(config.project)
        fixed_in_version = get_latest_open_version(project, config.version_prefix)

        if not fixed_in_version:
            logger.info('Unable to determine latest version for %s', project.name)
            return

        for issue in get_issues(redmine, issue_ids):
            if issue.project.id == project.id:
                logger.info('Setting fixed in version for issue %s to %s', issue.id,
                            fixed_in_version.name)
                set_fixed_in_version(issue, fixed_in_version)



if __name__ == "__main__":
    run_app(
        name='prprocessor',
        version='0.1.0',
        url='https://github.com/apps/prprocessor',
    )
