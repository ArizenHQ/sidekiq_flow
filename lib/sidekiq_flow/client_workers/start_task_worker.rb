module SidekiqFlow
  module ClientWorker
    class TaskStarterWorker
      include Sidekiq::Worker

      def perform(workflow_id, task_class)
        task = Client.find_task(workflow_id, task_class)
        raise TaskUnstartable unless task.pending?

        Client.enqueue_task(task, Time.now.to_i)
      end
    end
  end
end
