# require rubygems and sinatra/base so you can run this application locally with ruby app.rb
require 'rubygems'
require 'sinatra/base'

class App < Sinatra::Base
  get '/' do
    # use the views/index.erb file
    erb :index
  end

  get '/agent' do
    # use the views/agent.erb file
    erb :agent
  end
  # start the server if this file is run directly
  run! if app_file == $0
end