require 'rubygems'
require 'json'
require 'rest_client'

# Issue model on the client side
class RedmineResource

  attr_reader :resource
  attr_accessor :base_path, :raw_data

  def initialize(path = nil, key = ENV['REDMINE_API_KEY'])
    site = 'https://projects.theforeman.org/'

    options = {}
    options[:headers] = {'X-Redmine-API-Key' => key} if key

    @resource = RestClient::Resource.new(site, options)
    self.raw_data = get(path)
  end

  def base_path
    '/'
  end

  def get(path = nil)
    JSON.parse(@resource[format_path(path)].get)
  end

  def post(path, payload)
    @resource[format_path(path)].post(payload.to_json, :content_type => :json)
  end

  def put(path, payload)
    @resource[format_path(path)].put(payload.to_json, :content_type => :json)
  end

  def delete(path)
    @resource[format_path(path)].delete
  end

  def format_path(path)
    if path
      "#{base_path}/#{path}.json"
    else
      "#{base_path}.json"
    end
  end

end
