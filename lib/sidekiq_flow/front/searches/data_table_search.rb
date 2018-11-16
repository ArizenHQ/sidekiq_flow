module SidekiqFlow
  module Front
    class DataTableSearch
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
            "<a href=\"#{app_prefix}/workflow/#{workflow_id}\">#{workflow_id}</a>",
            workflow_started_at,
            workflow_succeeded_at,
            "<a href=\"#{app_prefix}/workflow/#{workflow_id}/destroy\" onclick=\"return confirm('Are you sure?')\"><i class='fas fa-trash'></i></a>"
          ]
        end
      end

      private

      attr_reader :value, :order_column_index, :order_dir, :start_index, :page_size, :app_prefix

      def get_input_data
        SidekiqFlow::Client.find_workflow_keys.map do |key|
          workflow_id, workflow_started_at, workflow_succeeded_at = key.split('.').last.split('_').map(&:to_i)
          [
            workflow_id.to_s,
            Time.at(workflow_started_at).to_s,
            workflow_succeeded_at.zero? ? '' : Time.at(workflow_succeeded_at).to_s
          ]
        end
      end
    end
  end
end
