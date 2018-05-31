module SidekiqFlow
  class Client
    class << self
      def run_workflow(workflow_class, workflow_id, params={})
        workflow = workflow_class.new(id: id, params: params)
        store_workflow(workflow)
        workflow.initial_tasks.each { |t| run_task(workflow.id, t) }
      end

      def run_task(workflow_id, task)
        task = task.new(status: Task::Statuses['enqueued'])
        enqueue_task(workflow_id, task) if task.start_date.present?
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

      def store_workflow(workflow, store_tasks=true)
        connection_pool.with do |redis|
          redis.set(workflow_key(workflow.id), workflow.to_json)
          workflow.tasks.each { |task| store_task(workflow.id, task) } if store_tasks
        end
      end

      def store_task(workflow_id, task)
        connection_pool.with do |redis|
          redis.set("#{workflow_key(workflow_id)}.#{task.class_name}", task.to_json)
        end
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

      def parse_json(json)
        JSON.parse(json).deep_symbolize_keys
      end

      def enqueue_task(workflow_id, task)
        Sidekiq::Client.push(
          {
            'class' => Worker,
            'args' => [workflow_id, task.class_name],
            'queue' => task.queue,
            'at' => task.start_date,
            'retry' => task.retries
          }
        )
      end
    end
  end
end
