import os
from dataclasses import dataclass
from typing import AbstractSet, MutableSet, Optional

from redminelib import Redmine
from redminelib.exceptions import ResourceNotFoundError
from redminelib.resources import Issue, Project


@dataclass
class IssueValidation:
    project: Optional[Project]
    valid_issues: AbstractSet[Issue]
    invalid_project_issues: AbstractSet[Issue]
    missing_issue_ids: AbstractSet[int]


def get_redmine() -> Redmine:
    # Handle the KeyError
    url = os.environ['REDMINE_URL']
    return Redmine(url)


def get_issues(redmine: Redmine, issue_ids: AbstractSet[int]) -> AbstractSet[Issue]:
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


def verify_issues(config, issue_ids: AbstractSet[int]) -> IssueValidation:
    correct_project = None
    issues: AbstractSet[Issue] = set()
    invalid_issues: AbstractSet[Issue] = set()
    missing_issue_ids: MutableSet[int] = set(issue_ids)

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

    valid_issues = issues - invalid_issues

    return IssueValidation(project=correct_project, valid_issues=valid_issues,
                           invalid_project_issues=invalid_issues,
                           missing_issue_ids=missing_issue_ids)
