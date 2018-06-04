module SidekiqFlow
  module TaskTriggerRules
    class AllSucceeded < Base
      def met?
        task_parents.all?(&:succeeded?)
      end
    end
  end
end
