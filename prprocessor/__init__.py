import re
from typing import Optional

PACKAGING_STABLE_BRANCH_REGEX = re.compile(r'(?:rpm|deb)/(?P<version>\d+\.\d+)')

def get_version_prefix_from_branch(target_branch: str) -> Optional[str]:
    """
    Get the version prefix, which is used to filter.

    For example, from 3.9-stable the prefix is 3.9. which can be used to filter on 3.9.* and find
    the latest open 3.9 version in Redmine.

    >>> get_version_prefix_from_branch('3.9-stable')
    '3.9.'
    >>> get_version_prefix_from_branch('KATELLO-4.10')
    '4.10.'
    >>> get_version_prefix_from_branch('develop')
    ''
    >>> get_version_prefix_from_branch('deb/develop')
    ''
    >>> get_version_prefix_from_branch('rpm/develop')
    ''
    >>> get_version_prefix_from_branch('rpm/3.9')
    '3.9'
    >>> get_version_prefix_from_branch('unknown') is None
    True
    """
    if target_branch.endswith('-stable'):
        # Handle a branch like 3.0-stable. This means we get an additional prefix of 3.0. which
        # allows get_latest_open_version to find the right version
        version_prefix = f'{target_branch.removesuffix("-stable")}.'
    elif target_branch.startswith('KATELLO-'):
        # Handle a branch like KATELLO-4.9. This means we get an additional prefix of 4.9. which
        # allows get_latest_open_version to find the right version
        version_prefix = f'{target_branch.removeprefix("KATELLO-")}.'
    elif target_branch in ('main', 'master', 'develop', 'deb/develop', 'rpm/develop'):
        # Development branches don't have a version prefix so they really use the latest
        version_prefix = ''
    else:
        match = PACKAGING_STABLE_BRANCH_REGEX.match(target_branch)
        if match:
            version_prefix = match.group('version')
        else:
            version_prefix = None

    return version_prefix


def is_stable_branch(branch_name: str) -> bool:
    """
    >>> is_stable_branch('develop')
    False
    >>> is_stable_branch('3.9-stable')
    True
    >>> is_stable_branch('unknown')
    False
    """
    version_prefix = get_version_prefix_from_branch(branch_name)
    return version_prefix is not None and version_prefix != ''
