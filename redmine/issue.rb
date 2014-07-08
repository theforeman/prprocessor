require File.join(File.dirname(__FILE__), 'redmine_resource')

# Issue model on the client side
class Issue < RedmineResource

  READY_FOR_TESTING = 7

  def base_path
    '/issues'
  end

  def update_status(status)
    @raw_data['issue']['status_id'] = status
    put(@raw_data['issue']['id'], @raw_data)
  end

  def set_version(version_id)
    @raw_data['issue']['fixed_version_id'] = status
    put(@raw_data['issue']['id'], @raw_data)
  end

  def project
    @raw_data['issue']['project']['id']
  end

  def update_pull_request(url)
    @raw_data['issue']['custom_field_values'] = {'7' => url}
    put(@raw_data['issue']['id'], @raw_data)
  end

end
