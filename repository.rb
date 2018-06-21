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

  def permitted_refs
    @config.fetch('refs', [])
  end

  def redmine_project
    @config['redmine']
  end

  def redmine_required?
    !!@config['redmine_required']
  end

  def link_to_redmine?
    @config['link_to_redmine']
  end

  def directory_labels
    @config['directory_labels']
  end

  def directory_labels?
    @config['directory_labels']
  end

  def branch_labels
    @config['branch_labels']
  end

  def branch_labels?
    @config['branch_labels']
  end

  def project_allowed?(identifier)
    ([redmine_project] + permitted_refs).include?(identifier)
  end
end
