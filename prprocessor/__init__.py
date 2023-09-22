from typing import Optional

def get_version_prefix_from_branch(target_branch: str) -> Optional[str]:
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
        return None

    return version_prefix
