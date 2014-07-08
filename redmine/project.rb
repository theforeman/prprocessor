require 'date'
require File.join(File.dirname(__FILE__), 'redmine_resource')

# Issue model on the client side
class Project < RedmineResource

  def base_path
    '/projects'
  end

  def get_versions
    get("#{@raw_data['project']['id']}/versions")
  end

  def current_version
    versions = get_versions['versions']
    versions.find do |version|
      Date.parse(version['due_date']) > Date.today
    end
  end

end
