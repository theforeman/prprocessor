def strip_suffix(value: str, suffix: str) -> str:
    """
    Remove the suffix like Python 3.9+ str.removesuffix does.

    >>> strip_suffix('2.4-stable', '-stable')
    '2.4'
    >>> strip_suffix('develop', '-stable')
    'develop'
    """
    if value.endswith(suffix):
        return value[:-len(suffix)]
    return value


def strip_prefix(value: str, prefix: str) -> str:
    """
    Remove the prefix like Python 3.9+ str.removeprefix does.

    >>> strip_prefix('foreman-3.3', 'foreman-')
    '3.3'
    >>> strip_prefix('katello-4.4', 'foreman-')
    'katello-4.4'
    >>> strip_prefix('develop', 'foreman-')
    'develop'
    """
    if value.startswith(prefix):
        return value[len(prefix):]
    return value
