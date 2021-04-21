module SidekiqFlow
  class Client
    class << self
      attr_writer :adapters

      def start_workflow(workflow, async: false)
        return if already_started?(workflow.id)

        if async
          Sidekiq::Client.push(
            {
              'class' => ClientWorker::WorkflowStarterWorker,
              'args' => [workflow.id, workflow.klass],
              'queue' => SidekiqFlow.configuration.queue
            }
          )
        else
          store_workflow(workflow, true)
          tasks = workflow.find_ready_to_start_tasks
          tasks.each { |task| enqueue_task(task) }
        end
      end

      def start_task(workflow_id, task_class, async: false)
        task = find_task(workflow_id, task_class)
        raise TaskUnstartable unless task.pending?

        if async
          Sidekiq::Client.push(
            {
              'class' => ClientWorker::TaskStarterWorker,
              'args' => [workflow_id, task_class],
              'queue' => SidekiqFlow.configuration.queue
            }
          )
        else
          enqueue_task(task, Time.now.to_i)
        end
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

      def store_workflow(workflow, initial = false)
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

      def find_workflow_keys
        adapters.last.find_workflow_keys
      end

      def enqueue_task(task, at = nil)
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
        adapters.last.find_workflow_key(workflow_id)
      end

      def set_task_queue(workflow_id, task_class, queue)
        task = find_task(workflow_id, task_class)
        task.set_queue!(queue)
        store_task(task)
      end

      def connection_pool
        adapters.last.connection_pool
      end

      def configuration
        @configuration ||= SidekiqFlow.configuration
      end

      private

      def adapters
        @adapters ||= [SidekiqFlow::Adapters::SetStorage.new(configuration)]
      end

      def already_started?(workflow_id)
        adapters.last.already_started?(workflow_id)
      end
    end
  end
end
