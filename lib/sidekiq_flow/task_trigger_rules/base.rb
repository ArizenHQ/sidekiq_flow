module SidekiqFlow
  module TaskTriggerRules
    class Base
      def self.build(trigger_rule, workflow_id, task_parent_classes)
        "#{parent}::#{trigger_rule.camelize}".constantize.new(workflow_id, task_parent_classes)
      end

      def initialize(workflow_id, task_parent_classes)
        @task_parents = task_parent_classes.map { |klass| Client.find_task(workflow_id, klass) }
      end

      def met?
        raise NotImplementedError
      end

      private

      attr_reader :task_parents
    end
  end
end
