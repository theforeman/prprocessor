#!/usr/bin/env ruby
require 'octokit'
require 'pp'
require 'date'
require 'yaml'
require File.expand_path(File.join('..', '..', 'repository'), __FILE__)
require File.expand_path(File.join('..', '..', 'github', 'pull_request'), __FILE__)
require File.expand_path(File.join('..', '..', 'redmine', 'issue'), __FILE__)

CONFIG = {}
CONFIG.merge!(YAML.load_file('config/close_inactive.yaml'))
CONFIG.merge!(YAML.load_file('config/local_close_inactive.yaml')) if File.exists?('config/local_close_inactive.yaml')

THRESHOLD = DateTime.now << CONFIG[:keep]
COMMENT = <<EOC
Thank you for your contribution, @%s! This PR has been inactive for #{CONFIG[:keep]} months, closing for now.
Feel free to reopen when you return to it. This is an automated process.
EOC

c = Octokit::Client.new(:access_token => ENV['GITHUB_OAUTH_TOKEN'])
Repository.all.select { |repo,config| config.close_inactive? }.each do |repo,config|
  query = "repo:#{repo} type:pr state:open label:\"Waiting on contributor\" updated:\"<#{THRESHOLD}\""
  result = c.search_issues(query, :per_page => CONFIG[:max_closed], :sort => 'updated_at', :order => 'asc')
  puts "Pull requests older than #{THRESHOLD}: #{result[:total_count]}"
  result[:items].each do |pr|
    title = pr[:title]
    number = pr[:number]
    user = pr[:user][:login]
    updated_at = pr[:updated_at].to_datetime
    labels = c.labels_for_issue(repo, number).collect{ |x| x[:name] }
    if updated_at < THRESHOLD && labels.include?("Waiting on contributor")
      puts "Closing #{number} (#{title}) with latest update #{updated_at}"
      c.add_comment(repo, number, COMMENT % user) if CONFIG[:add_comment]
      c.add_labels_to_an_issue(repo, number, CONFIG[:labels]) if CONFIG[:add_labels]
      c.close_pull_request(repo, number) if CONFIG[:close]

      pr_obj = PullRequest.new(repo, pr)
      pr_obj.issue_numbers.map { |issue| Issue.new(issue) }.each do |issue|
        issue.set_assigned(nil)
        issue.set_status(Issue::NEW)
        issue.remove_pull_request(pr[:html_url])
        issue.save!
      end
    end
  end
end

