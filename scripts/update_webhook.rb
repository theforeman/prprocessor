#!/usr/bin/env ruby

require 'octokit'
require 'yaml'

if ENV['GITHUB_AUTH_TOKEN'].nil?
  abort("GITHUB_AUTH_TOKEN is needed to access the GitHub API")
end

repos = YAML.load_file('../config/repos.yaml').keys

Octokit.configure do |c|
  c.access_token = ENV['GITHUB_AUTH_TOKEN']
end

new_url = "https://prprocessor.theforeman.org/pull_request"
old_url = "http://prprocessor.theforeman.org/pull_request"

repos.each do |repo|
  puts "Checking #{repo} : https://api.github.com/repos/#{repo}/hooks"
  hooks = Octokit.hooks(repo)

  hook_to_update = hooks.find do |hook|
    hook.config.url == old_url
  end

  if hook_to_update
    Octokit.edit_hook(
      repo,
      hook_to_update.id,
      'web',
      {:url => new_url}
    )

    puts "Hook updated for #{repo}"
  else
    puts "No update needed for #{repo}"
  end
end
