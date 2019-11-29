import logging
import os
from dataclasses import dataclass
from distutils.version import LooseVersion  # pylint: disable=no-name-in-module,import-error
from typing import AbstractSet, Generator, Iterable, MutableSet, Optional

from redminelib import Redmine
from redminelib.exceptions import ResourceNotFoundError
from redminelib.resources import CustomField, Issue, Project


logger = logging.getLogger(__name__)  # pylint: disable=invalid-name


FIXED_IN_VERSIONS_FIELD_ID = 12  # TODO hardcoded ID


@dataclass
class IssueValidation:
    project: Optional[Project]
    valid_issues: AbstractSet[Issue]
    invalid_project_issues: AbstractSet[Issue]
    missing_issue_ids: AbstractSet[int]


def get_redmine() -> Redmine:
    # Handle the KeyError
    url = os.environ['REDMINE_URL']
    key = os.environ.get('REDMINE_KEY')
    return Redmine(url, key=key)


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


def set_fixed_in_version(issue: Issue, version: CustomField) -> None:
    field = issue.custom_fields.get(FIXED_IN_VERSIONS_FIELD_ID)
    # For some reason field values are strings
    version_id = str(version.id)
    if version_id not in field.value:
        issue.save(custom_fields=[{'id': field.id, 'value': field.value + [version_id]}])


def get_latest_open_version(project: Project, version_prefix: Optional[str]) \
        -> Optional[CustomField]:
    versions = _filter_versions(project.versions.filter(status='open'), version_prefix)

    try:
        return sorted(versions, key=lambda version: LooseVersion(version.name))[-1]
    except ValueError:
        logger.exception('Failed to parse version for %s: %s', project.name, versions)
        return None
    except IndexError:
        logger.warning('No versions found for %s', project.name)
        return None


def strip_prefix(value: str, prefix: Optional[str]) -> str:
    if prefix and value.startswith(prefix):
        return value[len(prefix):]
    return value


def _filter_versions(versions: Iterable[CustomField],
                     version_prefix: str) -> Generator[CustomField, None, None]:
    for version in versions:
        name = strip_prefix(version.name, version_prefix)
        if name and name[0].isdigit():
            yield version
