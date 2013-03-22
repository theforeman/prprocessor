# require rubygems and sinatra so you can run this application locally with ruby app.rb
require 'rubygems'
require 'sinatra'

get '/' do
  "the time where this server lives is #{Time.now}
    <br /><br />check out your <a href=\"/agent\">user_agent</a>"
end

get '/agent' do
  "you're using #{request.user_agent}"
end