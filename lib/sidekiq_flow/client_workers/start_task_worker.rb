module SidekiqFlow
  module ClientWorker
    class TaskStarterWorker
      include Sidekiq::Worker

      def perform(workflow_id, task_class)
        Client.enqueue_task(task, Time.now.to_i)
      end
    end
  end
end
