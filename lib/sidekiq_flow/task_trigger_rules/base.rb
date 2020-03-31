module SidekiqFlow
  module TaskTriggerRules
    class Base
      def self.build(trigger_rule, trigger_rule_extra_opts, workflow, task_parent_klasses)
        "#{parent}::#{trigger_rule.camelize}".constantize.new(workflow, task_parent_klasses, trigger_rule_extra_opts)
      end

      def initialize(workflow, task_parent_klasses, extra_opts)
        @extra_opts = extra_opts
        @task_parents = task_parent_klasses.map { |klass| workflow.find_task(klass) }
      end

      def met?
        raise NotImplementedError
      end

      private

      attr_reader :task_parents, :extra_opts
    end
  end
end
