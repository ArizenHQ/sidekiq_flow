module SidekiqFlow
  class Error < StandardError; end
  class WorkflowNotFound < Error; end
  class SkipTask < Error; end
  class RepeatTask < Error; end
end
