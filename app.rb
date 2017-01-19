require 'sinatra'
require 'json'
require 'openssl'
require 'yaml'

require File.join(File.dirname(__FILE__), 'redmine/issue')
require File.join(File.dirname(__FILE__), 'redmine/project')
require File.join(File.dirname(__FILE__), 'github/pull_request')
require File.join(File.dirname(__FILE__), 'github/status')
require File.join(File.dirname(__FILE__), 'jenkins')
require File.join(File.dirname(__FILE__), 'repository')


post '/pull_request' do
  actions = {}

  request.body.rewind
  payload_body = request.body.read
  verify_signature(payload_body)

  event = request.env['HTTP_X_GITHUB_EVENT']
  halt unless ['pull_request', 'pull_request_review', 'pull_request_review_comment'].include?(event)

  payload = JSON.parse(payload_body)
  action = payload['action']
  event_act = "#{event}/#{action}"

  raise "unknown repo" unless payload['repository'] && (repo_name = payload['repository']['full_name'])
  raise "repo not configured" if Repository[repo_name].nil?
  repo = Repository[repo_name]

  client = Octokit::Client.new(:access_token => ENV['GITHUB_OAUTH_TOKEN'])
  pull_request = PullRequest.new(repo, payload['pull_request'], client)
  pr_number = pull_request.raw_data['number']

  halt if event == 'pull_request' && ['closed', 'labeled', 'unlabeled'].include?(action)
  # also trigger for new PullRequestReviewCommentEvent containing [test]
  halt if event_act == 'pull_request_review_comment/created' && (!payload['comment'] || !payload['comment']['body'].include?('[test]'))

  if ENV['REDMINE_API_KEY'] && !repo.redmine_project.nil?
    users = YAML.load_file('config/users.yaml')

    pull_request.issue_numbers.each do |issue_number|
      issue = Issue.new(issue_number)
      project = Project.new(issue.project)

      user_id = users[pull_request.author] if users.key?(pull_request.author)

      if !([repo.redmine_project] + repo.permitted_refs).include?(project.identifier)
        if ENV['GITHUB_OAUTH_TOKEN']
          correct_project = Project.new(repo.redmine_project)
          message = <<EOM
@#{pull_request.author}, the Redmine ticket used is for a different project than the one associated with this GitHub repository. Please either:

* check [##{issue_number}: #{issue.subject}](http://projects.theforeman.org/issues/#{issue_number}) is the correct one
* move [ticket ##{issue_number}](http://projects.theforeman.org/issues/#{issue_number}) from #{project.name} to the #{correct_project.name} project
* or file a new ticket in the [#{correct_project.name} project](http://projects.theforeman.org/projects/#{repo.redmine_project}/issues/new)

If changing the ticket number used, remember to update the PR title and the commit message (using `git commit --amend`).

---------------------------------------
This message was auto-generated by Foreman's [prprocessor](http://projects.theforeman.org/projects/foreman/wiki/PrProcessor)
EOM
          pull_request.labels = ['Waiting on contributor']
          pull_request.add_comment(message)
        end
      elsif !issue.rejected?
        if project.name == 'Katello' && issue.release == 'Backlog'
          issue.set_release(nil)
        end

        issue.add_pull_request(pull_request.raw_data['html_url'])
        issue.set_status(Issue::READY_FOR_TESTING) unless issue.closed?
        issue.set_assigned(user_id) unless user_id.nil? || user_id.empty? || issue.assigned_to
        issue.save!

        actions['redmine'] = true
      end
    end
  end

  if ENV['GITHUB_OAUTH_TOKEN']
    if repo.link_to_redmine?
      pull_request.add_issue_links
    end

    if event_act == 'pull_request/synchronize' && pull_request.waiting_for_contributor?
      if pull_request.not_yet_reviewed?
        pull_request.replace_labels(['Waiting on contributor'], ['Needs testing'])
      else
        pull_request.replace_labels(['Waiting on contributor'], ['Needs testing', 'Needs re-review'])
      end
    end

    pull_request.check_commits_style if repo.redmine_required? && (event_act == 'pull_request/opened' || event_act == 'pull_request/synchronize')

    pull_request.labels = ["Needs testing", "Not yet reviewed"] if event_act == 'pull_request/opened'

    if event_act == 'pull_request_review/submitted' && ['rejected', 'changes_requested'].include?(payload['review']['state'])
      pull_request.replace_labels(['Not yet reviewed', 'Needs re-review'], ['Waiting on contributor'])
    end

    if pull_request.dirty?
      message = <<EOM
@#{pull_request.author}, this pull request is currently not mergeable. Please rebase against the #{pull_request.target_branch} branch and push again.

If you have a remote called 'upstream' that points to this repository, you can do this by running:

```
    $ git pull --rebase upstream #{pull_request.target_branch}
```

---------------------------------------
This message was auto-generated by Foreman's [prprocessor](http://projects.theforeman.org/projects/foreman/wiki/PrProcessor)
EOM
      pull_request.replace_labels(['Needs testing', 'Needs re-review', 'Not yet reviewed'], ['Waiting on contributor'])
      pull_request.add_comment(message)
    end

    pull_request.set_directory_labels(repo.directory_labels) if repo.directory_labels?

    actions['github'] = true
  end

  if ENV['JENKINS_TOKEN'] && repo.pr_scanner?
    jenkins = Jenkins.new
    jenkins.build(repo.name, pr_number)
    actions['jenkins'] = true
  end

  actions.to_json
end

get '/status' do
  locals = {}
  locals[:jenkins_token] = ENV['JENKINS_TOKEN'] ? true : false
  locals[:github_secret] = ENV['GITHUB_SECRET_TOKEN'] ? true : false
  locals[:redmine_key] = ENV['REDMINE_API_KEY'] ? true : false
  locals[:github_oauth_token] = ENV['GITHUB_OAUTH_TOKEN'] ? true : false
  locals[:configured_repos] = Repository.all.keys
  locals[:rate_limit] = Status.new.rate_limit

  erb :status, :locals => locals
end

# Hash of Redmine projects to linked GitHub repos
get '/redmine_repos' do
  Repository.all.select { |repo,config| !config.redmine_project.nil? }.inject({}) do |output,(repo,config)|
    output[config.redmine_project] ||= {}
    output[config.redmine_project][repo] = config.branches
    output
  end.to_json
end

def verify_signature(payload_body)
  signature = 'sha1=' + OpenSSL::HMAC.hexdigest(OpenSSL::Digest.new('sha1'), ENV['GITHUB_SECRET_TOKEN'], payload_body)
  return halt 500, "Signatures didn't match!" unless Rack::Utils.secure_compare(signature, request.env['HTTP_X_HUB_SIGNATURE'])
end
