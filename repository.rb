require 'yaml'

class Repository
  def self.all
    @repos ||= begin
      Hash[YAML.load_file(File.join(File.dirname(__FILE__), 'config', 'repos.yaml')).map do |repo,config|
        [repo, Repository.new(repo, config || {})]
      end]
    end
  end

  def self.[](repo)
    all[repo]
  end

  attr_reader :full_name

  def initialize(full_name, config = {})
    @full_name = full_name
    @config = config

    if @config.has_key?('redmine_required') && !@config.has_key?('redmine')
      raise("Repo #{full_name} is missing 'redmine' config key")
    end
  end

  def branches
    @config['branches']
  end

  def close_inactive?
    !!@config['close_inactive']
  end

  def name
    full_name.split('/').last
  end

  def organization
    full_name.split('/').first
  end

  def pr_scanner?
    !!@config.fetch('pr_scanner', false)
  end

  def redmine_project
    @config['redmine']
  end

  def redmine_required?
    !!@config['redmine_required']
  end
end
