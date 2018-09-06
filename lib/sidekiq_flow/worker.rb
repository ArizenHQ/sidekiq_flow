module SidekiqFlow
  class Worker
    include Sidekiq::Worker

    sidekiq_retries_exhausted do |msg|
      task = Client.find_task(*msg['args'])
      task.fail!
      Client.store_task(task)
    end

    def perform(workflow_id, task_class)
      task = Client.find_task(workflow_id, task_class)
      return unless task.enqueued?
      if task.auto_succeed?
        task.succeed!
      elsif task.expired?
        task.fail!
      else
        perform_task(task)
      end
      Client.store_task(task)
      enqueue_task_children(task)
    end

    private

    def perform_task(task)
      task.perform
    rescue SkipTask
      task.skip!
    rescue RepeatTask
      Client.enqueue_task(task, (Time.now + task.loop_interval).to_i)
    rescue StandardError
      task.no_retries? ? task.fail! : task.await_retry!
      Client.store_task(task)
      raise
    else
      task.succeed!
    end

    def enqueue_task_children(task)
      task.children.each do |child_class|
        child_task = Client.find_task(task.workflow_id, child_class)
        next unless child_task.ready_to_start?
        Client.enqueue_task(child_task)
        Client.store_task(child_task)
      end
    end
  end
end
