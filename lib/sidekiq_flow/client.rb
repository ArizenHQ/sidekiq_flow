module SidekiqFlow
  class Client
    SCAN_COUNT = 2000

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
        store_task(task)
      end

      def store_workflow(workflow, initial=false)
        workflow_key = initial ? generate_initial_workflow_key(workflow.id) : find_workflow_key(workflow.id)
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
        return unless workflow_succeeded?(task.workflow_id)
        succeed_workflow(task.workflow_id)
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

      def destroy_succeeded_workflows
        workflow_keys = find_workflow_keys(succeeded_workflow_key_pattern)
        return if workflow_keys.empty?
        connection_pool.with do |redis|
          redis.del(*workflow_keys)
        end
      end

      def find_task(workflow_id, task_class)
        find_workflow(workflow_id).find_task(task_class)
      end

      def find_workflow_keys(pattern=workflow_key_pattern)
        connection_pool.with do |redis|
          redis.scan_each(match: pattern, count: SCAN_COUNT).to_a
        end
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
        connection_pool.with do |redis|
          redis.scan_each(match: "#{configuration.namespace}.#{workflow_id}_*", count: SCAN_COUNT).first
        end
      end

      def set_task_queue(workflow_id, task_class, queue)
        task = find_task(workflow_id, task_class)
        task.set_queue!(queue)
        store_task(task)
      end

      def connection_pool
        @connection_pool ||= ConnectionPool.new(size: configuration.concurrency, timeout: 5) do
          Redis.new(url: configuration.redis_url)
        end
      end

      private

      def configuration
        @configuration ||= SidekiqFlow.configuration
      end

      def generate_initial_workflow_key(workflow_id)
        "#{configuration.namespace}.#{workflow_id}_#{Time.now.to_i}_0"
      end

      def workflow_succeeded?(workflow_id)
        find_workflow(workflow_id).succeeded?
      end

      def succeed_workflow(workflow_id)
        current_key = find_workflow_key(workflow_id)

        # NOTE: Race condition. Some other task might have renamed/deleted the key already.
        return if current_key.blank?

        connection_pool.with do |redis|
          redis.rename(current_key, current_key.chop.concat(Time.now.to_i.to_s))
        end
      end

      def workflow_key_pattern
        "#{configuration.namespace}.*"
      end

      def succeeded_workflow_key_pattern
        "#{configuration.namespace}.*_*_[^0]*"
      end

      def already_started?(workflow_id)
        key = nil

        connection_pool.with do |redis|
          key = redis.scan_each(match: already_started_workflow_key_pattern(workflow_id), count: SCAN_COUNT).first
        end

        key.present?
      end

      def already_started_workflow_key_pattern(workflow_id)
        "#{configuration.namespace}.#{workflow_id}_*_0"
      end
    end
  end
end
