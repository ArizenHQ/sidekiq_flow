module SidekiqFlow
  module Front
    class WorkflowSerializer < SimpleDelegator
      def to_h
        __getobj__.to_h.merge(klass: klass, tasks: tasks.map { |t| t.to_h.merge(klass: t.klass, name: t.to_s) })
      end

      def to_json
        to_h.to_json
      end
    end
  end
end
