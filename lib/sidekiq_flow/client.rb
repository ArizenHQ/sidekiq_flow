module SidekiqFlow
  class Client
    class << self
      def start_workflow(workflow)
        store_workflow(workflow)
        workflow.initial_tasks.each { |t| start_task(workflow.id, t) }
      end

      def start_task(workflow_id, task, external_trigger=false)
        # TODO: return if parents didn't succeed
        return if task.start_date.nil? && !external_trigger
        task = task.set_job(enqueue_worker(workflow_id, task, external_trigger ? Time.now.to_i : task.start_date)).enqueue
        store_task(workflow_id, task)
      end

      def find_workflow(workflow_id)
        connection_pool.with do |redis|
          workflow_key = workflow_key(workflow_id)
          workflow_json = redis.get(workflow_key)
          raise WorkflowNotFound if workflow_json.nil?

          tasks = redis.mget(*redis.scan_each(match: "#{workflow_key}.*")).map do |task_json|
            Model.from_hash(parse_json(task_json))
          end
          Model.from_hash(parse_json(workflow_json).merge(tasks: tasks))
        end
      end

      def find_task(workflow_id, task_class_name)
        connection_pool.with do |redis|
          Model.from_hash(parse_json(redis.get(task_key(workflow_id, task_class_name))))
        end
      end

      def store_workflow(workflow, store_tasks=true)
        connection_pool.with do |redis|
          redis.set(workflow_key(workflow.id), workflow.to_json)
        end
        workflow.tasks.each { |task| store_task(workflow.id, task) } if store_tasks
      end

      def store_task(workflow_id, task)
        connection_pool.with do |redis|
          redis.set(task_key(workflow_id, task.class_name), task.to_json)
        end
      end

      def enqueue_worker(workflow_id, task, enqueue_at)
        Sidekiq::Client.push(
          {
            'class' => Worker,
            'args' => [workflow_id, task.class_name],
            'queue' => task.queue,
            'at' => enqueue_at,
            'retry' => task.retries
          }
        )
      end

      private

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

      def task_key(workflow_id, task_class_name)
        "#{workflow_key(workflow_id)}.#{task_class_name}"
      end

      def parse_json(json)
        JSON.parse(json).deep_symbolize_keys
      end
    end
  end
end
