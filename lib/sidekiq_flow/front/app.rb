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
          request.path[0...-request.path_info.size]
        end
      end

      get %r{/(js|css)/.+} do |asset_type|
        env['PATH_INFO'].sub!("/#{asset_type}", '')
        settings.environment.call(env)
      end

      get '/' do
        erb :index
      end

      get '/workflows' do
        search = DataTableSearch.new(
          params.dig('search', 'value'),
          params.dig('order', '0', 'column').to_i,
          params.dig('order', '0', 'dir'),
          params['start'].to_i,
          params['length'].to_i,
          app_prefix
        )
        search.execute!

        json(
          recordsTotal: search.input_data_size,
          recordsFiltered: search.filtered_data_size,
          data: search.data
        )
      end

      get '/workflow/:id' do |id|
        @workflow = WorkflowSerializer.new(SidekiqFlow::Client.find_workflow(id))
        erb :workflow
      end

      get '/workflow/:id/destroy' do |id|
        SidekiqFlow::Client.destroy_workflow(id)
        redirect "#{app_prefix}/"
      end

      get '/workflows/succeeded/destroy' do
        SidekiqFlow::Client.destroy_succeeded_workflows
        redirect "#{app_prefix}/"
      end

      get '/workflow/:workflow_id/task/:task_class/retry' do |workflow_id, task_class|
        SidekiqFlow::Client.restart_task(workflow_id, task_class)
        ''
      end

      get '/workflow/:workflow_id/task/:task_class/clear' do |workflow_id, task_class|
        SidekiqFlow::Client.clear_task(workflow_id, task_class)
        ''
      end
    end
  end
end
