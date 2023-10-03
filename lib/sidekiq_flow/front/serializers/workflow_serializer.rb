module SidekiqFlow
  module Front
    class WorkflowSerializer < SimpleDelegator
      def to_h
        __getobj__.to_h.merge(klass: klass, tasks: tasks.map { |t| task_hash(t) })
      end

      def to_json
        to_h.to_json
      end

      private

      def task_hash(task)
        task.to_h.merge(
          klass: task.klass,
          name: task.to_s,
          start_date: formatted_date(task.start_date),
          end_date: formatted_date(task.end_date)
        )
      end

      def formatted_date(timestamp)
        return if timestamp.nil?

        Time.at(timestamp)
      end
    end
  end
end
