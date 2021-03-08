module SidekiqFlow
  class Client

    class << self

      def start_workflow(workflow)
        return if already_started?(workflow.id)
      
        store_workflow(workflow, true)
        tasks = workflow.find_ready_to_start_tasks
        tasks.each { |task| enqueue_task(task) }
      end
      
      def start_task(workflow_id, task_class)
        task = find_task(workflow_id, task_class)
        raise TaskUnstartable unless task.pending?
        enqueue_task(task, Time.now.to_i)
      end
      
      def restart_task(workflow_id, task_class)
        task = find_task(workflow_id, task_class)
        return if task.enqueued? || task.awaiting_retry?
        workflow = find_workflow(workflow_id)
        workflow.clear_branch!(task_class)
        store_workflow(workflow)
        start_task(workflow_id, task_class)
      end
      
      def clear_task(workflow_id, task_class)
        task = find_task(workflow_id, task_class)
        task.clear!
        task.clear_dates!
        store_task(task)
      end

      def store_workflow(workflow, initial=false)
        adapters.each { |adapter| adapter.store_workflow(workflow, initial) }
      end

      def store_task(task)
        adapters.each { |adapter| adapter.store_task(task) }
      end

      def find_workflow(workflow_id)
        adapters.last.find_workflow(workflow_id)
      end

      def destroy_workflow(workflow_id)
        adapters.each { |adapter| adapter.destroy_workflow(workflow_id) }
      end

      def destroy_succeeded_workflows
        adapters.each { |adapter| adapter.destroy_succeeded_workflows }
      end

      def find_task(workflow_id, task_class)
        find_workflow(workflow_id).find_task(task_class)
      end

      def find_workflow_keys(pattern=workflow_key_pattern)
        adapters.last.find_workflow_keys(workflow_key_pattern)
      end

      def enqueue_task(task, at=nil)
        task.enqueue!
        store_task(task)
        Sidekiq::Client.push(
          {
            'class' => Worker,
            'args' => [task.workflow_id, task.klass],
            'queue' => task.queue,
            'at' => at || task.start_date,
            'retry' => task.retries
          }
        )
        TaskLogger.log(task.workflow_id, task.klass, :info, 'task enqueued')
      end
  
      def find_workflow_key(workflow_id)
        key_pattern = "#{configuration.namespace}.#{workflow_id}_*"

        adapters.last.find_first(key_pattern)
      end
  
      def set_task_queue(workflow_id, task_class, queue)
        task = find_task(workflow_id, task_class)
        task.set_queue!(queue)
        store_task(task)
      end

      def connection_pool
        adapters.each { |adapter| adapter.connection_pool }
      end

      private

      def adapters
        @adapters ||= [SidekiqFlow::Adapters::LegacyStorage]
      end

      def configuration
        @configuration ||= SidekiqFlow.configuration
      end

      def workflow_key_pattern
        "#{configuration.namespace}.*"
      end
  
      def already_started?(workflow_id)
        key_pattern = already_started_workflow_key_pattern(workflow_id)
  
        adapters.last.find_first(key_pattern).present?
      end
  
      def already_started_workflow_key_pattern(workflow_id)
        "#{configuration.namespace}.#{workflow_id}_*_0"
      end

    end
  end
end
