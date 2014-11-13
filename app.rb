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

  halt unless request.env['HTTP_X_GITHUB_EVENT'] == 'pull_request'

  payload = JSON.parse(payload_body)
  raise "unknown repo" unless payload['repository'] && (repo = payload['repository']['name'])

  pull_request = PullRequest.new(payload['pull_request'])
  pr_number = pull_request.raw_data['number']
  pr_action = payload['action']

  halt if ['labeled', 'unlabeled'].include?(pr_action)

  pull_request.check_commits_style if ENV['REDMINE_ISSUE_REQUIRED_REPOS'].to_s.split.include? pull_request.repo

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

  if payload['action'] == 'opened'
    pull_request.set_labels
  end

  jenkins = Jenkins.new
  jenkins.build(repo, pr_number)

end

get '/status' do
  locals = {}
  locals[:jenkins_token] = ENV['JENKINS_TOKEN'] ? true : false
  locals[:github_secret] = ENV['GITHUB_SECRET_TOKEN'] ? true : false
  locals[:redmine_key] = ENV['REDMINE_API_KEY'] ? true : false
  locals[:github_oauth_token] = ENV['GITHUB_OAUTH_TOKEN'] ? true : false

  erb :status, :locals => locals
end

def verify_signature(payload_body)
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['GITHUB_SECRET_TOKEN'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end
