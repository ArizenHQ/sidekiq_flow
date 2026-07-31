module SidekiqFlow
  module Front
    class WorkflowsSearch
      attr_reader :input_data_size, :filtered_data_size, :data

      def initialize(value, order_column_index, order_dir, start_index, page_size, app_prefix)
        @value = value
        @order_column_index = order_column_index
        @order_dir = order_dir
        @start_index = start_index
        @page_size = page_size
        @app_prefix = app_prefix
      end

      def execute!
        @data = get_input_data()
        @input_data_size = @data.size

        # filtering
        if value.present?
          @data.select! do |row|
            row.any? { |entry| entry.match?(value) }
          end
        end
        @filtered_data_size = @data.size

        # ordering
        @data.sort_by! { |row| row.at(order_column_index) }
        @data.reverse! if order_dir == 'desc'

        # paginating
        @data = (@data.each_slice(page_size).to_a.presence || [[]]).at(start_index / page_size)

        # decorating
        @data.map! do |workflow_id, workflow_started_at, workflow_succeeded_at|
          [
            "<a class='font-mono text-indigo-600 hover:text-indigo-500 hover:underline' href=\"#{app_prefix}/workflow/#{workflow_id}\">#{workflow_id}</a>",
            workflow_started_at,
            workflow_succeeded_at,
            "<a class='inline-flex items-center justify-center rounded-full p-1.5 text-slate-400 hover:bg-red-50 hover:text-red-600 transition-colors' " \
              "href=\"#{app_prefix}/workflow/#{workflow_id}/destroy\" onclick=\"return confirm('Are you sure?')\" aria-label='Destroy workflow'>" \
              "<svg class='w-4 h-4' viewBox='0 0 20 20' fill='currentColor' aria-hidden='true'>" \
              "<path fill-rule='evenodd' d='M8.75 1A2.75 2.75 0 0 0 6 3.75v.443c-.795.077-1.584.176-2.365.298a.75.75 0 1 0 .23 1.482l.149-.022.841 10.518A2.75 2.75 0 0 0 7.596 19h4.807a2.75 2.75 0 0 0 2.742-2.53l.841-10.52.149.023a.75.75 0 0 0 .23-1.482A41.03 41.03 0 0 0 14 4.193V3.75A2.75 2.75 0 0 0 11.25 1h-2.5ZM10 4c.84 0 1.673.025 2.5.075V3.75c0-.69-.56-1.25-1.25-1.25h-2.5c-.69 0-1.25.56-1.25 1.25v.325C8.327 4.025 9.16 4 10 4ZM8.58 7.72a.75.75 0 0 0-1.5.06l.3 7.5a.75.75 0 1 0 1.5-.06l-.3-7.5Zm4.34.06a.75.75 0 1 0-1.5-.06l-.3 7.5a.75.75 0 1 0 1.5.06l.3-7.5Z' clip-rule='evenodd' />" \
              '</svg></a>'
          ]
        end
      end

      private

      attr_reader :value, :order_column_index, :order_dir, :start_index, :page_size, :app_prefix

      def get_input_data
        SidekiqFlow::Client.find_workflow_keys.map do |key|
          m = key.match(/^#{SidekiqFlow.configuration.namespace}.([^_]+)_(\d+)_(\d+)$/)

          if m
            workflow_id           = m[1]
            workflow_started_at   = m[2].to_i
            workflow_succeeded_at = m[3].to_i

            [
              workflow_id,
              Time.at(workflow_started_at).to_s,
              workflow_succeeded_at.to_i.zero? ? '' : Time.at(workflow_succeeded_at).to_s
            ]
          else
            nil
          end
        end.compact
      end
    end
  end
end
