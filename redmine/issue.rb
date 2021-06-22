require File.join(File.dirname(__FILE__), 'redmine_resource')

# Issue model on the client side
class Issue < RedmineResource

  NEW = 1
  FIELD_PULL_REQUEST = 7

  def base_path
    '/issues'
  end

  def project
    @raw_data['issue']['project']['id']
  end

  def subject
    @raw_data['issue']['subject']
  end

  def version_name
    @raw_data['issue']['fixed_version']['name'] if @raw_data['issue']['fixed_version']
  end

  def version
    @raw_data['issue']['fixed_version']['id'] if @raw_data['issue']['fixed_version']
  end

  def set_status(status)
    @raw_data['issue']['status_id'] = status
    self
  end

  def pull_requests
    field = @raw_data['issue']['custom_fields'].find { |f| f['id'] == FIELD_PULL_REQUEST }
    return nil if field.nil?
    field['value']
  end

  def set_pull_requests(url)
    @raw_data['issue']['custom_field_values'] = {FIELD_PULL_REQUEST.to_s => url}
    self
  end

  def remove_pull_request(url)
    current_pull_requests = pull_requests
    set_pull_requests(current_pull_requests - [url]) unless current_pull_requests.nil?
  end

  def set_assigned(user_id)
    @raw_data['issue']['assigned_to_id'] = user_id
    self
  end

  def save!
    put(@raw_data['issue']['id'], @raw_data)
  end

  def to_s
    "#{project} ##{@raw_data['issue']['id']}"
  end
end
