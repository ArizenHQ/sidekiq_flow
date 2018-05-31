module SidekiqFlow
  class Worker
    include Sidekiq::Worker

    def perform(workflow_id, task_class_name)
      # TODO: continue here
    end
  end
end
