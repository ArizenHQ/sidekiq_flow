module SidekiqFlow
  class Worker

    include Sidekiq::Worker

    DEFAULT_RETRY_DELAY = 5.seconds

    sidekiq_retries_exhausted do |msg|
      task = Client.find_task(*msg['args'])
      task.fail!
      TaskLogger.log(msg['args'][0], msg['args'][1], :warn, 'task retries exhausted')
      Client.store_task(task)
    end

    def perform(workflow_id, task_class)
      TaskLogger.log(workflow_id, task_class, :info, 'task started')
      task = Client.find_task(workflow_id, task_class)
      return if !task.inline? && !task.enqueued? && !task.awaiting_retry?

      if task.succeeded?
        TaskLogger.log(workflow_id, task_class, :info, 'task already succeeded')
      elsif task.auto_succeed?
        task.succeed!
        TaskLogger.log(workflow_id, task_class, :info, 'task succeeded')
      elsif task.expired?
        TaskLogger.log(workflow_id, task_class, :warn, 'task expired')
        task.set_error_msg!('expired')
        task.fail!
      else
        perform_task(task)
      end
      Client.store_task(task)
      enqueue_or_perform_children(task) unless task.pending?
    end

    private

    def perform_task(task)
      task.perform
    rescue TriggerTaskManually
      task.clear!
      task.clear_dates!
      TaskLogger.log(task.workflow_id, task.klass, :info, 'task set to pending (to be triggered manually)')
    rescue SkipTask
      task.skip!
      TaskLogger.log(task.workflow_id, task.klass, :info, 'task skipped')
    rescue RepeatTask
      Client.enqueue_task(task, (Time.now + task.loop_interval).to_i)
    rescue TryLater => e
      Client.enqueue_task(task, (Time.now + e.delay_time).to_i)
    rescue StandardError => e
      task.set_error_msg!(e.to_s)
      if task.no_retries?
        task.fail!
        TaskLogger.log(task.workflow_id, task.klass, :error, "task failed (no retries) - #{e}")
      else
        task.await_retry!
        TaskLogger.log(task.workflow_id, task.klass, :error, "task failed (retries present) - #{e}")
      end
      Client.store_task(task)
      raise
    else
      task.succeed!
      TaskLogger.log(task.workflow_id, task.klass, :info, 'task succeeded')
    end

    def enqueue_or_perform_children(task)
      task.children.each do |child_class|
        child_task = Client.find_task(task.workflow_id, child_class)
        next unless child_task.ready_to_start?

        if child_task.ready_to_perform_inline?
          begin
            perform(child_task.workflow_id, child_class)
          rescue StandardError
            Client.enqueue_task(child_task, (Time.now + DEFAULT_RETRY_DELAY).to_i) if child_task.awaiting_retry?
          end
        else
          Client.enqueue_task(child_task)
        end
      end
    end

  end
end
