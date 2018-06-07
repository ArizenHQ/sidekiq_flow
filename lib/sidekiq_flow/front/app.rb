require 'sinatra'
require 'sprockets'
require 'uglifier'
require 'sidekiq_flow'

module SidekiqFlow
  module Front
    class App < Sinatra::Base
      enable :logging
      set :server, :thin
      set :environment, Sprockets::Environment.new(File.dirname(__FILE__))

      environment.append_path 'assets/stylesheets'
      environment.append_path 'assets/javascripts'
      environment.js_compressor  = :uglify
      environment.css_compressor = :scss

      helpers do
        def app_prefix
          request.fullpath[0...-request.path_info.size]
        end
      end

      get %r{/(js|css)/.+} do |asset_type|
        env['PATH_INFO'].sub!("/#{asset_type}", '')
        settings.environment.call(env)
      end

      get '/' do
        @worklow_ids = SidekiqFlow::Client.find_workflow_ids
        erb :index
      end

      get '/workflow/:id' do |id|
        @workflow = SidekiqFlow::Client.find_workflow(id)
        erb :workflow
      end

      get '/workflow/:workflow_id/task/:task_class/clear' do |workflow_id, task_class|
        workflow = SidekiqFlow::Client.find_workflow(workflow_id)
        SidekiqFlow::Client.clear_workflow_branch(workflow, task_class)
        SidekiqFlow::Client.run_workflow(workflow)
        ''
      end
    end
  end
end
