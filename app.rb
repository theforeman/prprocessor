require 'sinatra'
require 'json'
require 'openssl'

require File.join(File.dirname(__FILE__), 'redmine/issue')
require File.join(File.dirname(__FILE__), 'redmine/project')
require File.join(File.dirname(__FILE__), 'github/pull_request')
require File.join(File.dirname(__FILE__), 'jenkins')


post '/pull_request' do
  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body)

  halt unless ['pull_request', 'pull_request_review_comment'].include?(request.env['HTTP_X_GITHUB_EVENT'])

  payload = JSON.parse(payload_body)
  raise "unknown repo" unless payload['repository'] && (repo = payload['repository']['name'])

  pull_request = PullRequest.new(payload['pull_request'])
  pr_number = pull_request.raw_data['number']
  pr_action = payload['action']

  halt if ['labeled', 'unlabeled'].include?(pr_action)
  # also trigger for new PullRequestReviewCommentEvent containing [test]
  halt if pr_action == 'created' && (!payload['comment'] || !payload['comment']['body'].include?('[test]'))

  pull_request.check_commits_style if redmine_issue_repos.find { |r| pull_request.repo.match(r) } && pr_action != 'created'

  pull_request.issue_numbers.each do |issue_number|
    issue = Issue.new(issue_number)
    project = Project.new(issue.project)
    current_version = project.current_version

    unless issue.rejected?
      issue.set_version(current_version['id']) if issue.version.nil? && current_version
      issue.set_pull_request(pull_request.raw_data['html_url']) if issue.pull_request.nil? || issue.pull_request.empty?
      issue.set_status(Issue::READY_FOR_TESTING) unless issue.closed?
      issue.save!
    end
  end

  if pr_action == 'synchronize' && pull_request.waiting_for_contributor?
    pull_request.replace_labels(['Waiting on contributor'], ['Needs testing', 'Needs re-review'])
  end

  pull_request.labels = ["Needs testing", "Not yet reviewed"] if pr_action == 'opened'

  jenkins = Jenkins.new
  jenkins.build(repo, pr_number)
end

get '/status' do
  locals = {}
  locals[:jenkins_token] = ENV['JENKINS_TOKEN'] ? true : false
  locals[:github_secret] = ENV['GITHUB_SECRET_TOKEN'] ? true : false
  locals[:redmine_key] = ENV['REDMINE_API_KEY'] ? true : false
  locals[:github_oauth_token] = ENV['GITHUB_OAUTH_TOKEN'] ? true : false
  locals[:redmine_issue_repos] = redmine_issue_repos

  erb :status, :locals => locals
end

def verify_signature(payload_body)
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['GITHUB_SECRET_TOKEN'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end

def redmine_issue_repos
  ENV['REDMINE_ISSUE_REQUIRED_REPOS'].to_s.split.map { |r| Regexp.new("\\A#{r}\\z") }
end
