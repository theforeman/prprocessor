#!/usr/bin/env ruby

require 'yaml'
require_relative '../github/user.rb'

user = User.new
members = user.organization_logins('theforeman')
members = members.concat(user.organization_logins('katello'))

members_map = {}
members_map = YAML.load_file('config/users.yaml') if File.exists?('config/users.yaml')

members.each do |member|
  members_map[member] = '' unless members_map.key?(member)
end

File.open('config/users.yaml', 'w') do |file|
  file.write(members_map.to_yaml)
end
