# require rubygems and sinatra/base so you can run this application locally with ruby app.rb
require 'rubygems'
require 'sinatra/base'

class App < Sinatra::Base
  get '/' do
    "the time where this server lives is #{Time.now}
      <br /><br />check out your <a href=\"/agent\">user_agent</a>"
  end

  get '/agent' do
    "you're using #{request.user_agent}"
  end
  # start the server if this file is run directly
  run! if app_file == $0
end