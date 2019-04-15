import logging
import re
from datetime import datetime, timezone

import yaml
from octomachinery.app.routing import process_event_actions
from octomachinery.app.routing.decorators import process_webhook_payload
from octomachinery.app.runtime.context import RUNTIME_CONTEXT
from octomachinery.app.server.runner import run as run_app
from pkg_resources import resource_filename

from prprocessor.redmine import verify_issues


COMMIT_VALID_SUMMARY_REGEX = re.compile(
        r'\A(fixes|refs) (?P<issues>#(\d+)(, ?#(\d+))*)(:| -) .*\Z',
        re.IGNORECASE,
)
COMMIT_ISSUES_REGEX = re.compile(r'#(\d+)')
CHECK_NAME = 'Redmine issues'

# This should be handled cleaner
with open(resource_filename(__name__, 'config/repos.yaml')) as config_fp:
    CONFIG = {
        repo: {
            'project': config.get('redmine'),
            'required': config.get('redmine_required'),
            'refs': set(config.get('refs', [])),
        }
        for repo, config in yaml.safe_load(config_fp).items()
    }


logger = logging.getLogger('prprocessor')  # pylint: disable=invalid-name


def summarize(summary):
    show_headers = len(summary) > 1
    for header, lines in summary.items():
        if show_headers:
            yield f'### {header}'
        for line in lines:
            yield f'* {line}'


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


async def validate_commits(config, pull_request):
    github_api = RUNTIME_CONTEXT.app_installation_client

    commits = await github_api.getitem(pull_request['commits_url'])

    issue_ids = set()
    warnings = []

    for commit in commits:
        message = commit['commit']['message']
        subject = message.splitlines()[0]

        match = COMMIT_VALID_SUMMARY_REGEX.match(subject)
        if match:
            for issue in COMMIT_ISSUES_REGEX.findall(match.group('issues')):
                issue_ids.add(int(issue))
        elif config['required']:
            sha = commit['sha']
            warnings.append(f"{sha} must be in the format `fixes #redmine - brief description`")

    result = {
        'Invalid commits': warnings,
    }
    return result, issue_ids


async def verify_pull_request(pull_request):
    config = CONFIG[pull_request['base']['repo']['full_name']]
    result = {}

    commit_results, issue_ids = await validate_commits(config, pull_request)
    result.update(commit_results)

    issue_results, text = verify_issues(config, issue_ids)
    result.update(issue_results)

    return result, text


async def run_pull_request_check(pull_request, check_run=None):
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
async def on_pr_modified(*, action, pull_request, **other):  # pylint: disable=unused-argument
    await run_pull_request_check(pull_request)


@process_event_actions('check_run', {'rerequested'})
@process_webhook_payload
async def on_check_run(*, check_run, **other):  # pylint: disable=unused-argument
    github_api = RUNTIME_CONTEXT.app_installation_client

    for pr_summary in check_run['pull_requests']:
        pull_request = await github_api.getitem(pr_summary['url'])
        await run_pull_request_check(pull_request, check_run)


@process_event_actions('check_suite', {'requested', 'rerequested'})
@process_webhook_payload
async def on_suite_run(*, check_suite, **other):  # pylint: disable=unused-argument
    github_api = RUNTIME_CONTEXT.app_installation_client

    check_runs = await github_api.getitem(check_suite['check_runs_url'],
                                          preview_api_version='antiope')

    for check_run in check_runs['check_runs']:
        if check_run['name'] == CHECK_NAME:
            break
    else:
        check_run = None

    for pr_summary in check_suite['pull_requests']:
        pull_request = await github_api.getitem(pr_summary['url'])
        await run_pull_request_check(pull_request, check_run)


if __name__ == "__main__":
    run_app(
        name='prprocessor',
        version='0.1.0',
        url='https://github.com/apps/prprocessor',
    )
