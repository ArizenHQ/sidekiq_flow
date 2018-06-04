module SidekiqFlow
  module TaskTriggerRules
    class OneSucceeded < Base
      def met?
        task_parents.any?(&:succeeded?)
      end
    end
  end
end
