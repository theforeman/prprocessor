require 'rubygems'
require 'bundler'
Bundler.require

if ENV['SENTRY_DSN']
  require 'raven'
  use Raven::Rack
end

require './app.rb'
run Sinatra::Application
