require 'sinatra'
require 'raven'
require 'json'
require 'openssl'
require 'yaml'

require File.join(File.dirname(__FILE__), 'redmine/issue')
require File.join(File.dirname(__FILE__), 'redmine/project')
require File.join(File.dirname(__FILE__), 'github/pull_request')
require File.join(File.dirname(__FILE__), 'github/status')
require File.join(File.dirname(__FILE__), 'repository')


post '/pull_request' do
  actions = {}

  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body)

  event = request.env['HTTP_X_GITHUB_EVENT']
  halt unless event == 'pull_request'

  payload = JSON.parse(payload_body)
  halt unless payload['action'] == 'opened'

  raise "unknown repo" unless payload['repository'] && (repo_name = payload['repository']['full_name'])
  raise "repo #{repo_name} not configured" if Repository[repo_name].nil?
  repo = Repository[repo_name]

  if ENV['GITHUB_OAUTH_TOKEN']
    if repo.link_to_redmine?
      client = Octokit::Client.new(:access_token => ENV['GITHUB_OAUTH_TOKEN'])
      pull_request = PullRequest.new(repo, payload['pull_request'], client)
      pull_request.add_issue_links
    end

    actions['github'] = true
  end

  content_type :json
  actions.to_json
end

get '/status' do
  locals = {}
  locals[:github_secret] = ENV['GITHUB_SECRET_TOKEN'] ? true : false
  locals[:redmine_key] = ENV['REDMINE_API_KEY'] ? true : false
  locals[:github_oauth_token] = ENV['GITHUB_OAUTH_TOKEN'] ? true : false
  locals[:configured_repos] = Repository.all.keys
  locals[:rate_limit] = Status.new.rate_limit

  erb :status, :locals => locals
end

def verify_signature(payload_body)
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['GITHUB_SECRET_TOKEN'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end
