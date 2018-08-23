module SidekiqFlow
  class Client
    class << self
      def start_workflow(workflow)
        store_workflow(workflow)
        tasks = workflow.find_ready_to_start_tasks
        tasks.each { |task| enqueue_task(task) }
        store_workflow(workflow)
      end

      def start_task(workflow_id, task_class)
        task = find_task(workflow_id, task_class)
        raise TaskUnstartable unless task.pending?
        enqueue_task(task, Time.now.to_i)
        store_task(task)
      end

      def restart_task(workflow_id, task_class)
        workflow = find_workflow(workflow_id)
        workflow.clear_branch!(task_class)
        store_workflow(workflow)
        start_task(workflow_id, task_class)
      end

      def store_workflow(workflow)
        workflow_key = generate_workflow_key(workflow)
        connection_pool.with do |redis|
          redis.hmset(
            workflow_key,
            [:klass, workflow.klass, :attrs, workflow.to_json] + workflow.tasks.map { |t| [t.klass, t.to_json] }.flatten
          )
        end
      end

      def store_task(task)
        connection_pool.with do |redis|
          redis.hset(find_workflow_key(task.workflow_id), task.klass, task.to_json)
        end
      end

      def find_workflow(workflow_id)
        connection_pool.with do |redis|
          workflow_redis_hash = redis.hgetall(find_workflow_key(workflow_id))
          raise WorkflowNotFound if workflow_redis_hash.empty?
          Workflow.from_redis_hash(workflow_redis_hash)
        end
      end

      def destroy_workflow(workflow_id)
        connection_pool.with do |redis|
          redis.del(find_workflow_key(workflow_id))
        end
      end

      def find_task(workflow_id, task_class)
        find_workflow(workflow_id).find_task(task_class)
      end

      def find_workflow_keys
        connection_pool.with do |redis|
          redis.scan_each(match: workflow_key_pattern).map { |key| key.split('.').last }
        end
      end

      def enqueue_task(task, at=nil)
        task.enqueue!
        Sidekiq::Client.push(
          {
            'class' => Worker,
            'args' => [task.workflow_id, task.klass],
            'queue' => task.queue,
            'at' => at || task.start_date,
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

      def find_workflow_key(workflow_id)
        connection_pool.with do |redis|
          redis.scan_each(match: "#{configuration.namespace}.#{workflow_id}_*").first
        end
      end

      def generate_workflow_key(workflow)
        current_key = find_workflow_key(workflow.id)
        return "#{configuration.namespace}.#{workflow.id}_#{Time.now.to_i}_0" if current_key.nil?
        return current_key unless workflow.succeeded?
        _id, started_at, succeeded_at = current_key.split('_').map(&:to_i)
        return current_key unless succeeded_at.zero?
        "#{configuration.namespace}.#{workflow.id}_#{started_at}_#{Time.now.to_i}"
      end

      def workflow_key_pattern
        "#{configuration.namespace}.*"
      end
    end
  end
end
