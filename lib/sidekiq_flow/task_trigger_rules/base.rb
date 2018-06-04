module SidekiqFlow
  module TaskTriggerRules
    class Base
      def self.build(trigger_rule, task_parents)
        "#{parent}::#{trigger_rule.camelize}".constantize.new(task_parents)
      end

      def initialize(task_parents)
        @task_parents = task_parents
      end

      def met?
        raise NotImplementedError
      end

      private

      attr_reader :task_parents
    end
  end
end
