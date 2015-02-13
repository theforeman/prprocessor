require 'octokit'

class Status

  attr_accessor :client, :rate_limit

  def initialize
    self.client     = Octokit::Client.new(:access_token => ENV['GITHUB_OAUTH_TOKEN'])
    self.rate_limit = client.rate_limit
  end
end
