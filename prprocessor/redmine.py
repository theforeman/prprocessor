import os

from redminelib import Redmine
from redminelib.exceptions import ResourceNotFoundError


def get_redmine():
    # Handle the KeyError
    url = os.environ['REDMINE_URL']
    return Redmine(url)


def format_redmine_issues(issues):
    return [f"[#{issue.id}: {issue.subject}]({issue.url})"
            for issue in sorted(issues, key=lambda issue: issue.id)]


def format_details(invalid_issues, correct_project):
    text = []
    for issue in invalid_issues:
        # Would be nice to get the new issue URL via a property
        text.append(f"""### [#{issue.id}: {issue.subject}]({issue.url})

* check [#{issue.id}]({issue.url}) is the intended issue
* move [ticket #{issue.id}]({issue.url}) from {issue.project.name} to the {correct_project.name} project
* or file a new ticket in the [{correct_project.name} project]({correct_project.url}/issues/new)
""")

    return '\n'.join(text)


def get_issues(redmine, issue_ids):
    # You can search for a comma separated string and find multiple
    issue_id = ','.join(map(str, sorted(issue_ids)))
    issues = set(redmine.issue.filter(issue_id=issue_id))

    # But that search sometimes misses issues that do exist
    for missing in issue_ids ^ {issue.id for issue in issues}:
        try:
            issues.add(redmine.issue.get(missing))
        except ResourceNotFoundError:
            pass

    return issues


def verify_issues(config, issue_ids):
    issues = set()
    invalid_issues = set()
    missing_issue_ids = issue_ids
    text = ''

    if issue_ids:
        redmine = get_redmine()
        issues = get_issues(redmine, issue_ids)

        if issues:
            missing_issue_ids -= {issue.id for issue in issues}

            if config.project:
                correct_project = redmine.project.get(config.project)
                refs = {redmine.project.get(ref).id for ref in config.refs}
                project_ids = {correct_project.id} | refs
                invalid_issues = {issue for issue in issues if issue.project.id not in project_ids}
                text = format_details(invalid_issues, correct_project)

    result = {
        'Invalid project': format_redmine_issues(invalid_issues),
        'Issues not found in redmine': missing_issue_ids,
        'Valid issues': format_redmine_issues(set(issues) - invalid_issues),
    }

    return result, text
