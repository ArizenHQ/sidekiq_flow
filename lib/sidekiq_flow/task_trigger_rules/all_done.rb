module SidekiqFlow
  module TaskTriggerRules
    class AllDone < Base
      def met?
        task_parents.all? { |t| t.skipped? || t.succeeded? }
      end
    end
  end
end
