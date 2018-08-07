module SidekiqFlow
  module TaskTriggerRules
    class Base
      def self.build(trigger_rule, trigger_rule_extra_opts, workflow_id, task_parent_classes)
        "#{parent}::#{trigger_rule.camelize}".constantize.new(workflow_id, task_parent_classes, trigger_rule_extra_opts)
      end

      def initialize(workflow_id, task_parent_classes, extra_opts)
        @extra_opts = extra_opts
        @task_parents = task_parent_classes.map { |klass| Client.find_task(workflow_id, klass) }
      end

      def met?
        raise NotImplementedError
      end

      private

      attr_reader :task_parents, :extra_opts
    end
  end
end
