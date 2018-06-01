module SidekiqFlow
  class Worker
    include Sidekiq::Worker

    sidekiq_retries_exhausted do |msg|
      workflow_id, task = msg['args'][0], Client.find_task(*msg['args'])
      task = task.clear_job.fail
      Client.store_task(workflow_id, task)
    end

    def perform(workflow_id, task_class_name)
      task = Client.find_task(workflow_id, task_class_name)
      task = task.expired? ? task.fail : task.run
      Client.store_task(workflow_id, task)
      return if task.expired?
      begin
        result = task.perform
        task =
          case result
          when Task::Results[:success]
            task.succeed
          when Task::Results[:skip]
            task.skip
            # TODO: skip flat children as well
          when Task::Results[:repeat]
            Client.enqueue_worker(workflow_id, task, (Time.now + task.loop_interval).to_i)
            task.enqueue
          end
        Client.store_task(workflow_id, task)
        task.children.each do |child_class_name|
          Client.start_task(workflow_id, Client.find_task(workflow_id, child_class_name))
        end
        # TODO: add clear_job mechanism
      rescue StandardError
        task = task.no_retries? ? task.fail : task.enqueue
        Client.store_task(workflow_id, task)
        raise
      end
    end
  end
end
