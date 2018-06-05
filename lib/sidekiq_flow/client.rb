module SidekiqFlow
  class Client
    class << self
      def run_workflow(workflow, externally_triggered_tasks=[])
        workflow.run!(externally_triggered_tasks)
        enqueue_jobs(workflow.id, workflow.find_enqueued_tasks)
        store_workflow(workflow)
      end

      def find_workflow(workflow_id)
        connection_pool.with do |redis|
          workflow_json = redis.get(workflow_key(workflow_id))
          raise WorkflowNotFound if workflow_json.nil?
          Workflow.from_hash(JSON.parse(workflow_json).deep_symbolize_keys)
        end
      end

      def clear_workflow_branch(workflow_id, parent_task_class)
        workflow = find_workflow(workflow_id)
        workflow.clear_branch!(parent_task_class)
        store_workflow(workflow)
      end

      def find_workflow_ids
        connection_pool.with do |redis|
          redis.scan_each(match: workflow_ids_pattern).map { |key| key.split('.').last }
        end
      end

      private

      def store_workflow(workflow)
        connection_pool.with do |redis|
          redis.set(workflow_key(workflow.id), workflow.to_h.to_json)
        end
      end

      def enqueue_jobs(workflow_id, tasks)
        tasks.each do |task|
          Sidekiq::Client.push(
            {
              'class' => Worker,
              'args' => [workflow_id, task.klass],
              'queue' => task.queue,
              'at' => task.enqueued_at,
              'retry' => task.retries
            }
          )
        end
      end

      def configuration
        @configuration ||= SidekiqFlow.configuration
      end

      def connection_pool
        @connection_pool ||= ConnectionPool.new(size: configuration.concurrency, timeout: 5) do
          Redis.new(url: configuration.redis_url)
        end
      end

      def workflow_key(workflow_id)
        "#{configuration.namespace}.#{workflow_id}"
      end

      def workflow_ids_pattern
        "#{configuration.namespace}.*"
      end
    end
  end
end
