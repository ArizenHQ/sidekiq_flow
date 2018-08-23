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
        @workflows = SidekiqFlow::Client.find_workflow_keys.map { |k| k.split('_').map(&:to_i) }
        erb :index
      end

      get '/workflow/:id' do |id|
        @workflow = WorkflowSerializer.new(SidekiqFlow::Client.find_workflow(id))
        erb :workflow
      end

      get '/workflow/:workflow_id/task/:task_class/retry' do |workflow_id, task_class|
        SidekiqFlow::Client.restart_task(workflow_id, task_class)
        ''
      end
    end
  end
end
