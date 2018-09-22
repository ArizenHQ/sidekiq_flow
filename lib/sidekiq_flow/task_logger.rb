module SidekiqFlow
  class TaskLogger
    def self.log(workflow_id, task_class, level, msg)
      SidekiqFlow.configuration.logger.public_send(level, "[#{workflow_id}][#{task_class}] " + msg)
    end
  end
end
