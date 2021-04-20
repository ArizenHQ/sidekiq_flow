module SidekiqFlow
  module ClientWorker
    class WorkflowStarterWorker
      include Sidekiq::Worker

      def perform(workflow_id, workflow_class)
        workflow = Kernel.const_get(workflow_class).new(id: workflow_id)
        Client.store_workflow(workflow, true)
        tasks = workflow.find_ready_to_start_tasks
        tasks.each { |task| Client.enqueue_task(task) }
      end
    end
  end
end
