import pytest

from prprocessor.redmine import strip_prefix


@pytest.mark.parametrize('value,prefix,expected', [
    ['foobar', None, 'foobar'],
    ['foobar', '', 'foobar'],
    ['foobar', 'foo', 'bar'],
    ['foofoobar', 'foo', 'foobar'],
])
def test_strip_prefix(value, prefix, expected):
    assert strip_prefix(value, prefix) == expected
