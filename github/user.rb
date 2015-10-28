require 'octokit'

class User

  attr_accessor :users, :client

  def initialize
    self.client = Octokit::Client.new(:access_token => ENV['GITHUB_OAUTH_TOKEN'], :auto_paginate => true)
  end

  def fetch_users(organization)
    @client.organization_members(organization)
  end

  def organization_logins(organization)
    fetch_users(organization).map(&:login)
  end

end
