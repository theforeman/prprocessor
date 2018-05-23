# Pull Request Processor for Foreman

prprocessor is a web service which receives GitHub webhooks/notifications and helps sync PRs to Redmine and Jenkins.

Documentation available [on the Foreman wiki](https://projects.theforeman.org/projects/foreman/wiki/PrProcessor).

## Environment Variables

* `ENV['GITHUB_OAUTH_TOKEN']`: An OAuth token with repos access to update PR labels
* `ENV['GITHUB_SECRET_TOKEN']`: The secret token for verifying GitHub webhooks
* `ENV['REDMINE_API_KEY']`: Redmine API key to use for making API update

## Configuration Files

* config/repos.yaml: List of GitHub repositories managed by this service
* config/users.yaml: List of GitHub usernames against Redmine user IDs to automatically assign tickets to PR authors.
