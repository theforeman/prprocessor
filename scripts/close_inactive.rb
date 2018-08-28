#!/usr/bin/env ruby
require 'raven'
require 'octokit'
require 'pp'
require 'date'
require 'yaml'
require File.expand_path(File.join('..', '..', 'repository'), __FILE__)
require File.expand_path(File.join('..', '..', 'github', 'pull_request'), __FILE__)
require File.expand_path(File.join('..', '..', 'redmine', 'issue'), __FILE__)

def close_prs(client, repo, config, label, time, message)
  query = "repo:#{repo} type:pr state:open label:\"#{label}\" updated:\"<#{time}\""
  result = client.search_issues(query, :per_page => CONFIG[:max_closed], :sort => 'updated_at', :order => 'asc')
  return if result[:total_count] == 0

  puts "Pull requests older than #{time}: #{result[:total_count]}"
  result[:items].each do |pr|
    title = pr[:title]
    number = pr[:number]
    user = pr[:user][:login]
    updated_at = pr[:updated_at].to_datetime
    labels = client.labels_for_issue(repo, number).collect{ |x| x[:name] }
    if updated_at < time && labels.include?(label)
      puts "Closing #{number} (#{title}) with latest update #{updated_at}"
      client.add_comment(repo, number, message % user) if CONFIG[:add_comment]
      client.add_labels_to_an_issue(repo, number, CONFIG[:labels]) if CONFIG[:add_labels]
      client.close_pull_request(repo, number) if CONFIG[:close]

      pr_obj = PullRequest.new(config, pr, client)
      pr_obj.issue_numbers.map { |issue| Issue.new(issue) }.each do |issue|
        issue.set_assigned(nil)
        issue.set_status(Issue::NEW)
        issue.remove_pull_request(pr[:html_url])
        issue.save!
      end
    end
  end
end

CONFIG = {}
CONFIG.merge!(YAML.load_file('config/close_inactive.yaml'))
CONFIG.merge!(YAML.load_file('config/local_close_inactive.yaml')) if File.exists?('config/local_close_inactive.yaml')

inactive_time = DateTime.now << CONFIG[:keep]
inactive_comment = <<EOC
Thank you for your contribution, @%s! This PR has been inactive for #{CONFIG[:keep]} months, closing for now.
Feel free to reopen when you return to it. This is an automated process.
EOC

impasse_time = DateTime.now << CONFIG[:impasse]
impasse_comment = <<EOC
Thank you for your contribution, @%s! This PR has reached an impasse with no new activity for #{CONFIG[:impasse]} months, closing for now.
Feel free to reopen if you feel an agreement can be reached. This is an automated process.
EOC

client = Octokit::Client.new(:access_token => ENV['GITHUB_OAUTH_TOKEN'])
Repository.all.select { |repo,config| config.close_inactive? }.each do |repo,config|
  close_prs(client, repo, config, "Waiting on contributor", inactive_time, inactive_comment)
  close_prs(client, repo, config, "Reached an impasse", impasse_time, impasse_comment)
end
