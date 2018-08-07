module SidekiqFlow
  module TaskTriggerRules
    class NumberSucceeded < Base
      def met?
        task_parents.count(&:succeeded?) >= extra_opts.fetch(:number)
      end
    end
  end
end
