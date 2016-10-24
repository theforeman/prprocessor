#!/bin/bash
set -e

if [ $# -eq 0 ]; then
  echo "Usage: $0 org/repo [org/repo2...]"
  exit 1
fi

if ! type jgrep >/dev/null 2>&1; then
  echo "requires jgrep"
  exit 1
fi

if [ -z "${GITHUB_SECRET_TOKEN}" ]; then
  echo "GITHUB_SECRET_TOKEN must be set"
  exit 1
fi

url=http://prprocessor-theforeman.rhcloud.com/pull_request

t=$(mktemp)
for repo in $*; do
  echo "Checking ${repo}"
  curl -n https://api.github.com/repos/${repo}/hooks > $t
  id=$(jgrep -i $t "name=web and config.url=${url}" -s id || :)
  if [ -n "$id" ]; then
    echo "Existing hook found on ${repo}, skipping"
    continue
  fi
  echo "Updating ${repo}, adding hook"
  curl -nd '
  {
    "name": "web",
    "active": true,
    "events": [
      "pull_request",
      "pull_request_review",
      "pull_request_review_comment"
    ],
    "config": {
      "url": "'${url}'",
      "content_type": "json",
      "secret": "'${GITHUB_SECRET_TOKEN}'"
    }
  }' -X POST https://api.github.com/repos/${repo}/hooks
done
rm -f $t
