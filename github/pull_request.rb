require 'octokit'
require 'retriable'
require 'uri'

class PullRequest

  attr_accessor :raw_data, :title, :repo, :number, :client

  def initialize(repo, raw_data, client)
    self.repo     = repo
    self.raw_data = raw_data
    self.title    = raw_data['title']
    self.number   = raw_data['number']
    self.client   = client
  end

  def new?
    @raw_data['created_at'] == @raw_data['updated_at']
  end

  def dirty?
    @raw_data['mergeable_state'] == 'dirty' && @raw_data['mergeable'] == false
  end

  def cherry_pick?
    @title.start_with?('CP') || @title.start_with?('[CP]') || @title.start_with?('Cherry picks for ')
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
    to_add = pr_labels & known_labels
    @client.add_labels_to_an_issue(repo.full_name, @number, to_add) if to_add.any?
  end

  def labels
    @client.labels_for_issue(repo.full_name, @number)
  end

  def label_names
    labels.map(&:name)
  end

  def pull_request
    @client.issue(repo.full_name, @number)
  end

  def commits
    if @commits.nil?
      # Sometimes the GitHub API returns a 404 immediately after PR creation
      Retriable.retriable :on => Octokit::NotFound, :interval => 2, :tries => 10 do
        @commits = client.pull_commits(repo.full_name, number)
      end
    end
    @commits
  end

  def issue_numbers
    if @issue_numbers.nil?
      # Find issue numbers from the most recent commit containing them
      @issue_numbers = []
      commits.reverse_each do |commit|
        commit.commit.message.scan(/([\s\(\[,-]|^)(fixes|refs)[\s:]+(#\d+([\s,;&]+#\d+)*)(?=[[:punct:]]|\s|<|$)/i) do |match|
          action, refs = match[1].to_s.downcase, match[2]
          next if action.empty?
          refs.scan(/#(\d+)/).each { |m| @issue_numbers << m[0].to_i }
        end
        break if !@issue_numbers.empty?
      end
    end
    @issue_numbers
  end

  def check_commits_style
    if cherry_pick?
      add_status('success', "PR is a Cherry-pick; commit message style not checked")
      return
    end

    short_warnings = Hash.new { |h, k| h[k] = [] }
    commits.each do |commit|
      if (commit.commit.message.lines.first =~ /\A(fixes|refs) #\d+(, ?#\d+)*(:| -) .*\Z/i) != 0
        short_warnings[commit.sha] << 'issue number format'
      end
      if commit.commit.author.email =~ /\A(vagrant@|root@)/
        short_warnings[commit.sha] << 'vagrant or root in commit author email'
      end
      if commit.commit.message.lines.first.chomp.size > 65
        short_warnings[commit.sha] << 'summary line length exceeded'
      end
    end

    if short_warnings.values.all?(&:empty?)
      add_status('success', "Commit message style is correct")
    else
      self.labels = ['Waiting on contributor']

      @commits.each do |commit|
        if short_warnings[commit.sha].empty?
          add_status('failure', "Some commit messages have an incorrect style", sha: commit.sha)
        else
          add_status('failure', "Commit message style: #{short_warnings[commit.sha].join(', ')}", sha: commit.sha)
        end
      end
    end
  end

  def add_issue_links
    if new? && issue_numbers.any? && !cherry_pick?
      message = issue_numbers.inject("Issues:") do |msg, issue_number|
        msg + " [##{issue_number}](https://projects.theforeman.org/issues/#{issue_number})"
      end

      add_comment(message)
    end
  end

  def not_yet_reviewed?
    label_names.include? 'Not yet reviewed'
  end

  def waiting_for_contributor?
    label_names.include? 'Waiting on contributor'
  end

  def replace_labels(remove_labels, add_labels)
    existing = label_names

    to_add = add_labels - existing
    to_remove = (remove_labels & existing) - add_labels

    to_remove.each do |label|
      @client.remove_label(repo.full_name, @number, label)
    end
    self.labels = to_add
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

  def get_labels(filename, mapping)
    mapping.select { |k, v| filename == k || filename.start_with?(k+"/") }.values
  end

  def get_desired_labels(files, mapping)
    files.collect { |f| get_labels(f.filename, mapping) }.flatten.compact.uniq
  end

  def set_path_labels(mapping)
    files = client.pull_files(repo.full_name, number)
    desired_labels = get_desired_labels(files, mapping) 

    to_remove = mapping.keys - desired_labels
    to_add = desired_labels

    replace_labels(to_remove, to_add)
  end

  def get_branch_labels(mapping)
    mapping.keep_if { |key, branch| target_branch =~ Regexp.new("^#{key}$") }.values
  end

  def set_branch_labels(mapping)
    self.labels = get_branch_labels(mapping) - label_names
  end

  def to_s
    "#{@repo}/#{@number}"
  end

  private

  def redmine_url
    "https://projects.theforeman.org/projects/#{repo.redmine_project}/issues/new"
  end
end
