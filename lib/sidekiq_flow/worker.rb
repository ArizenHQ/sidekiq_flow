module SidekiqFlow
  class Worker
    include Sidekiq::Worker

    sidekiq_retries_exhausted do |msg|
      workflow = Client.find_workflow(msg['args'][0])
      task = workflow.find_task(msg['args'][1])
      task.fail!
      Client.run_workflow(workflow)
    end

    def perform(workflow_id, task_class)
      workflow = Client.find_workflow(workflow_id)
      task = workflow.find_task(task_class)
      return unless task.runnable?
      task.expired? ? task.fail! : perform_task(workflow, task)
      Client.run_workflow(workflow)
    end

    private

    def perform_task(workflow, task)
      task.perform
    rescue SkipTask
      task.skip!
    rescue RepeatTask
      task.enqueue!((Time.now + task.loop_interval).to_i)
    rescue StandardError
      task.no_retries? ? task.fail! : task.await_retry!
      Client.run_workflow(workflow)
      raise
    else
      task.succeed!
    end
  end
end
