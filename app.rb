require 'sinatra'
require 'json'
require 'openssl'

require File.join(File.dirname(__FILE__), 'redmine/issue')
require File.join(File.dirname(__FILE__), 'github/pull_request')
require File.join(File.dirname(__FILE__), 'jenkins')


post '/pull_request' do
  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body)

  payload = JSON.parse(params[:payload])
  raise "unknown repo" unless payload['repository'] && (repo = payload['repository']['name'])

  pull_request = PullRequest.new(payload['pull_request'])
  pr_number = pull_request.raw_data['number']
  project = payload['repo']['owner']['login']

  if pull_request.new?
    issue = Issue.new(pull_request.issue_number)
    project = Project.new(issue.project)
    current_version = project.current_version

    issue.update_status(Issue::READY_FOR_TESTING)
    issue.set_version(current_version)
    issue.update_pull_request(pull_request.raw_data['html_url'])
  end

  jenkins = Jenkins.new
  jenkins.build(repo, pr_number)

end

get '/status' do
  locals = {}
  locals[:jenkins_token] = ENV['JENKINS_TOKEN'] ? true : false
  locals[:github_secret] = ENV['GITHUB_SECRET_TOKEN'] ? true : false
  locals[:redmine_key] = ENV['REDMINE_API_KEY'] ? true : false

  erb :status, :locals => locals
end

def verify_signature(payload_body)
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['GITHUB_SECRET_TOKEN'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end
