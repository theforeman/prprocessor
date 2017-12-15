require 'octokit'
require 'retriable'
require 'uri'

class PullRequest

  attr_accessor :raw_data, :title, :issue_numbers, :repo,
    :number, :client, :commits

  def initialize(repo, raw_data, client)
    self.repo     = repo
    self.raw_data = raw_data
    self.title    = raw_data['title']
    self.number   = raw_data['number']

    # Sometimes the GitHub API returns a 404 immediately after PR creation
    Retriable.retriable :on => Octokit::NotFound, :interval => 2, :tries => 10 do
      self.commits = client.pull_commits(repo.full_name, number)
    end

    # Find issue numbers from the most recent commit containing them
    self.issue_numbers = []
    commits.reverse_each do |commit|
      commit.commit.message.scan(/([\s\(\[,-]|^)(fixes|refs)[\s:]+(#\d+([\s,;&]+#\d+)*)(?=[[:punct:]]|\s|<|$)/i) do |match|
        action, refs = match[1].to_s.downcase, match[2]
        next if action.empty?
        refs.scan(/#(\d+)/).each { |m| self.issue_numbers << m[0].to_i }
      end
      break if !self.issue_numbers.empty?
    end
  end

  def new?
    @raw_data['created_at'] == @raw_data['updated_at']
  end

  def dirty?
    @raw_data['mergeable_state'] == 'dirty' && @raw_data['mergeable'] == false
  end

  def wip?
    @title.start_with?('WIP') || @title.start_with?('[WIP]')
  end

  def author
    @raw_data['user']['login']
  end

  def target_branch
    @raw_data['base']['ref']
  end

  def known_labels
    @known_labels ||= @client.labels(repo.full_name).map(&:name)
  end

  def labels=(pr_labels)
    @client.add_labels_to_an_issue(repo.full_name, @number, pr_labels & known_labels)
  end

  def labels
    @client.labels_for_issue(repo.full_name, @number)
  end

  def pull_request
    @client.issue(repo.full_name, @number)
  end

  def check_commits_style
    if wip?
      add_status('failure', "PR is Work in Progress; commit message style not checked")
      return
    end

    warnings = ''
    short_warnings = Hash.new { |h, k| h[k] = [] }
    @commits.each do |commit|
      next if commit.commit.message.lines.first =~ /^_/
      if (commit.commit.message.lines.first =~ /\A(fixes|refs) #\d+(, ?#\d+)*(:| -) .*\Z/i) != 0
        warnings += "  * #{commit.sha} must be in the format ```fixes #redmine_number - brief description```\n"
        short_warnings[commit.sha] << 'issue number format'
      end
      if commit.commit.message.lines.first.chomp.size > 65
        warnings += "  * length of the first commit message line for #{commit.sha} exceeds 65 characters\n"
        short_warnings[commit.sha] << 'summary line length exceeded'
      end
      commit.commit.message.lines.each do |line|
        if line.chomp.sub(URI.regexp, '').size > 72 && line !~ /^\s{4,}/
          warnings += "  * commit message for #{commit.sha} is not wrapped at 72nd column\n"
          short_warnings[commit.sha] << 'line length exceeded'
        end
      end
    end
    message = <<EOM
There were the following issues with the commit message:
#{warnings}

If you don't have a ticket number, please [create an issue in Redmine](#{redmine_url}).

For temporary commits (e.g. during review process), try to start the message with underscore character.

More guidelines are available in [Coding Standards](http://theforeman.org/handbook.html#Codingstandards) or on [the Foreman wiki](http://projects.theforeman.org/projects/foreman/wiki/Reviewing_patches-commit_message_format).

---------------------------------------
This message was auto-generated by Foreman's [prprocessor](http://projects.theforeman.org/projects/foreman/wiki/PrProcessor)
EOM
    unless warnings.empty?
      add_comment(message)
      self.labels = ['Waiting on contributor']

      @commits.each do |commit|
        if short_warnings[commit.sha].empty?
          add_status('failure', "Some commit messages have an incorrect style", sha: commit.sha)
        else
          add_status('failure', "Commit message style: #{short_warnings[commit.sha].join(', ')}", sha: commit.sha)
        end
      end
    else
      add_status('success', "Commit message style is correct")
    end
  end

  def add_issue_links
    if new? && issue_numbers.any?
      message = issue_numbers.inject("Issues:") do |msg, issue_number|
        msg + " [##{issue_number}](http://projects.theforeman.org/issues/#{issue_number})"
      end
      add_comment(message)
    end
  end

  def not_yet_reviewed?
    labels.map { |label| label[:name] }.include? 'Not yet reviewed'
  end

  def waiting_for_contributor?
    labels.map { |label| label[:name] }.include? 'Waiting on contributor'
  end

  def replace_labels(remove_labels, add_labels)
    remove_labels.each do |label|
      @client.remove_label(repo.full_name, @number, label) if labels.find { |existing| existing[:name] == label }
    end
    self.labels = add_labels
  end

  def add_comment(message)
    @last_comment = @client.add_comment(repo.full_name, @number, message)
  end

  def add_status(state, message, options = {})
    options = {
      url: @last_comment ? @last_comment.html_url : "https://theforeman.org/handbook.html",
      sha: commits.last.sha
    }.merge(options)
    @client.create_status(repo.full_name, options[:sha], state, context: 'prprocessor', description: message, target_url: options[:url])
  end

  private

  def redmine_url
    "http://projects.theforeman.org/projects/#{repo.redmine_project}/issues/new"
  end
end
