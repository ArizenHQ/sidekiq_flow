module SidekiqFlow
  class Error < StandardError; end
  class WorkflowNotFound < Error; end
  class TaskUnstartable < Error; end
  class SkipTask < Error; end
  class RepeatTask < Error; end

  class TryLater < Error
    attr_reader :delay_time

    def initialize(delay_time:)
      @delay_time = delay_time.to_i
    end
  end
end
