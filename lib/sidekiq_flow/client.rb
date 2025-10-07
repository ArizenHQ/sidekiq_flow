module SidekiqFlow
  class Client
    SCAN_COUNT = 2000

    class << self
      # Initiates a new workflow by storing it in Redis and enqueuing its initial tasks
      # @param workflow [Workflow] the workflow instance to start
      # @return [void]
      def start_workflow(workflow)
        return if already_started?(workflow.id)

        store_workflow(workflow, true)
        tasks = workflow.find_ready_to_start_tasks
        tasks.each { |task| enqueue_task(task) }
      end

      # Manually starts a specific task within a workflow
      # @param workflow_id [String, Integer] the workflow identifier
      # @param task_class [String] the task class name
      # @return [void]
      # @raise [TaskUnstartable] if the task is not in pending status
      def start_task(workflow_id, task_class)
        task = find_task(workflow_id, task_class)

        raise TaskUnstartable, "Cannot start #{task_class} with status: #{task.status}" unless task.pending?

        enqueue_task(task, Time.now.to_i)
      end

      # Restarts a task and clears all downstream dependent tasks
      # @param workflow_id [String, Integer] the workflow identifier
      # @param task_class [String] the task class name
      # @return [void]
      def restart_task(workflow_id, task_class)
        task = find_task(workflow_id, task_class)
        return if task.enqueued? || task.awaiting_retry?

        workflow = find_workflow(workflow_id)
        workflow.clear_branch!(task_class)
        store_workflow(workflow)
        start_task(workflow_id, task_class)
      end

      # Resets a task to its initial state by clearing its status and timestamps
      # @param workflow_id [String, Integer] the workflow identifier
      # @param task_class [String] the task class name
      # @return [void]
      def clear_task(workflow_id, task_class)
        task = find_task(workflow_id, task_class)
        task.clear!
        task.clear_dates!
        store_task(task)
      end

      # Persists the entire workflow and all its tasks to Redis as a hash
      # @param workflow [Workflow] the workflow instance to store
      # @param initial [Boolean] whether this is the first time storing this workflow
      # @return [void]
      def store_workflow(workflow, initial = false)
        workflow_key = initial ? generate_initial_workflow_key(workflow.id) : find_workflow_key(workflow.id)

        if workflow_key.blank?
          logger.error("Workflow[#{workflow.id}] Cannot store workflow: workflow_key not found")
          return
        end

        connection_pool.with do |redis|
          redis.hmset(
            workflow_key,
            [:klass, workflow.klass, :attrs, workflow.to_json] + workflow.tasks.map { |t| [t.klass, t.to_json] }.flatten
          )
        end
      end

      # Updates a single task's state in Redis and marks workflow as succeeded if complete
      # @param task [Task] the task instance to store
      # @return [void]
      def store_task(task)
        connection_pool.with do |redis|
          workflow_key = find_workflow_key(task.workflow_id)

          if workflow_key.blank?
            logger.error("Workflow[#{task.workflow_id}][#{task.klass}] Cannot store task: workflow_key not found")
            return
          end

          redis.hset(workflow_key, task.klass, task.to_json)
        end
        return unless workflow_succeeded?(task.workflow_id)

        succeed_workflow(task.workflow_id)
      end

      # Retrieves a workflow from Redis and reconstructs it as a Workflow object
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [Workflow] the reconstructed workflow instance
      # @raise [WorkflowNotFound] if the workflow doesn't exist in Redis
      def find_workflow(workflow_id)
        connection_pool.with do |redis|
          workflow_key = find_workflow_key(workflow_id)
          raise WorkflowNotFound if workflow_key.blank?

          workflow_redis_hash = redis.hgetall(workflow_key)
          raise WorkflowNotFound if workflow_redis_hash.empty?

          Workflow.from_redis_hash(workflow_redis_hash)
        end
      end

      # Removes a workflow and all its associated data from Redis
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [void]
      def destroy_workflow(workflow_id)
        workflow_key = find_workflow_key(workflow_id)
        return if workflow_key.blank?

        connection_pool.with do |redis|
          redis.pipelined do |pipeline|
            pipeline.del(workflow_key)
            pipeline.del("#{timestamp_namespace}.#{workflow_id}.start")
            pipeline.del("#{timestamp_namespace}.#{workflow_id}.end")
          end
        end

        delete_workflow_key(workflow_id)
      end

      # Batch deletes all completed workflows from Redis
      # @return [void]
      def destroy_succeeded_workflows
        workflow_keys = find_workflow_keys(succeeded_workflow_key_pattern)
        return if workflow_keys.empty?

        workflow_ids = workflow_keys.map { |key| key.match(/#{configuration.namespace}\.(\d+)_/)[1] }
        timestamp_keys = workflow_ids.flat_map { |id| ["#{timestamp_namespace}.#{id}.start", "#{timestamp_namespace}.#{id}.end"] }

        connection_pool.with do |redis|
          redis.pipelined do |pipeline|
            pipeline.del(*workflow_keys, *timestamp_keys)
            workflow_ids.each { |id| pipeline.hdel(workflow_keys_namespace, id) }
          end
        end
      end

      # Finds a specific task within a workflow
      # @param workflow_id [String, Integer] the workflow identifier
      # @param task_class [String] the task class name
      # @return [Task] the task instance
      def find_task(workflow_id, task_class)
        find_workflow(workflow_id).find_task(task_class)
      end

      # Scans Redis for all workflow keys matching a pattern
      # @param pattern [String] the Redis key pattern to match
      # @return [Array<String>] list of matching workflow keys
      def find_workflow_keys(pattern = workflow_key_pattern)
        connection_pool.with do |redis|
          redis.scan_each(match: pattern, count: SCAN_COUNT).to_a
        end
      end

      # Marks a task as enqueued and adds it to the Sidekiq queue
      # @param task [Task] the task instance to enqueue
      # @param at [Integer, nil] optional timestamp to schedule the task
      # @return [void]
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

      # Looks up the Redis key for a workflow using the lookup hash with fallback to legacy method
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [String, nil] the Redis key or nil if not found
      def find_workflow_key(workflow_id)
        # Try new lookup hash first
        workflow_key = lookup_workflow_key(workflow_id)
        return workflow_key if workflow_key.present?

        # Fallback to old timestamp-based lookup for existing workflows
        workflow_key = build_workflow_key_from_timestamps(workflow_id)

        # If found via fallback, migrate it to the new lookup hash
        if workflow_key.present?
          store_workflow_key(workflow_id, workflow_key)
        end

        workflow_key
      end

      # Changes the Sidekiq queue for a specific task
      # @param workflow_id [String, Integer] the workflow identifier
      # @param task_class [String] the task class name
      # @param queue [String] the new queue name
      # @return [void]
      def set_task_queue(workflow_id, task_class, queue)
        task = find_task(workflow_id, task_class)
        task.set_queue!(queue)
        store_task(task)
      end

      # Provides a connection pool for Redis operations
      # @return [ConnectionPool] the Redis connection pool
      def connection_pool
        @connection_pool ||=
          ConnectionPool.new(size: configuration.concurrency, timeout: configuration.timeout) do
            configuration.redis || Redis.new(url: configuration.redis_url)
          end
      end

      private

      # Returns the SidekiqFlow configuration object
      # @return [Configuration] the configuration instance
      def configuration
        @configuration ||= SidekiqFlow.configuration
      end

      # Returns the configured logger instance
      # @return [Logger] the logger instance
      def logger
        configuration.logger
      end

      # Creates the initial Redis key for a new workflow and stores it in the lookup hash
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [String] the generated workflow key
      def generate_initial_workflow_key(workflow_id)
        timestamp = Time.now.to_i

        store_start_timestamp(workflow_id, timestamp)

        workflow_key = "#{configuration.namespace}.#{workflow_id}_#{timestamp}_0"
        store_workflow_key(workflow_id, workflow_key)

        workflow_key
      end

      # Checks if all tasks in the workflow have succeeded
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [Boolean] true if workflow is complete
      def workflow_succeeded?(workflow_id)
        find_workflow(workflow_id).succeeded?
      end

      # Marks a workflow as succeeded by renaming its key with an end timestamp
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [void]
      def succeed_workflow(workflow_id)
        current_key = find_workflow_key(workflow_id)

        # NOTE: Race condition. Some other task might have renamed/deleted the key already.
        return if current_key.blank?

        return if already_succeeded?(workflow_id, current_key)

        timestamp = Time.now.to_i
        new_key = current_key.chop.concat(timestamp.to_s)

        connection_pool.with do |redis|
          redis.pipelined do |pipeline|
            pipeline.set("#{timestamp_namespace}.#{workflow_id}.end", timestamp)
            pipeline.rename(current_key, new_key)
          end
        end

        # Update lookup hash with new key
        store_workflow_key(workflow_id, new_key)
      end

      # Returns the Redis pattern to match all workflow keys
      # @return [String] the pattern for scanning workflow keys
      def workflow_key_pattern
        "#{configuration.namespace}.*"
      end

      # Returns the Redis pattern to match only completed workflow keys
      # @return [String] the pattern for scanning succeeded workflow keys
      def succeeded_workflow_key_pattern
        "#{configuration.namespace}.*_*_[^0]*"
      end

      # Checks if a workflow has been started by looking for its key
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [Boolean] true if workflow exists in Redis
      def already_started?(workflow_id)
        find_workflow_key(workflow_id).present?
      end

      # Checks if a workflow key indicates the workflow has completed
      # @param workflow_id [String, Integer] the workflow identifier
      # @param workflow_key [String] the Redis key to check
      # @return [MatchData, nil] match result if succeeded, nil otherwise
      def already_succeeded?(workflow_id, workflow_key)
        workflow_key.match(/#{configuration.namespace}\.#{workflow_id}_\d{10}_\d{10}/)
      end

      # Returns the Redis namespace for workflow timestamp keys
      # @return [String] the timestamp namespace
      def timestamp_namespace
        'workflow-timestamps'
      end

      # Stores the workflow start timestamp in Redis
      # @param workflow_id [String, Integer] the workflow identifier
      # @param timestamp [Integer] the Unix timestamp
      # @return [void]
      def store_start_timestamp(workflow_id, timestamp)
        connection_pool.with do |redis|
          redis.set("#{timestamp_namespace}.#{workflow_id}.start", timestamp)
        end
      end

      # Returns the Redis namespace for the workflow key lookup hash
      # @return [String] the workflow keys namespace
      def workflow_keys_namespace
        'workflow-keys'
      end

      # Retrieves a workflow key from the lookup hash
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [String, nil] the workflow key or nil if not found
      def lookup_workflow_key(workflow_id)
        connection_pool.with do |redis|
          redis.hget(workflow_keys_namespace, workflow_id)
        end
      end

      # Stores a workflow key in the lookup hash for fast retrieval
      # @param workflow_id [String, Integer] the workflow identifier
      # @param workflow_key [String] the Redis key to store
      # @return [void]
      def store_workflow_key(workflow_id, workflow_key)
        connection_pool.with do |redis|
          redis.hset(workflow_keys_namespace, workflow_id, workflow_key)
        end
      end

      # Removes a workflow key from the lookup hash
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [void]
      def delete_workflow_key(workflow_id)
        connection_pool.with do |redis|
          redis.hdel(workflow_keys_namespace, workflow_id)
        end
      end

      # Legacy method that rebuilds a workflow key from timestamp keys (fallback for old workflows)
      # @param workflow_id [String, Integer] the workflow identifier
      # @return [String, nil] the reconstructed workflow key or nil if timestamps missing
      def build_workflow_key_from_timestamps(workflow_id)
        start_timestamp, end_timestamp = connection_pool.with do |redis|
          redis.pipelined do |pipeline|
            pipeline.get("#{timestamp_namespace}.#{workflow_id}.start")
            pipeline.get("#{timestamp_namespace}.#{workflow_id}.end")
          end
        end

        workflow_key = if end_timestamp && start_timestamp
                         "#{configuration.namespace}.#{workflow_id}_#{start_timestamp}_#{end_timestamp}"
                       elsif start_timestamp
                         "#{configuration.namespace}.#{workflow_id}_#{start_timestamp}_0"
                       end

        # Sanity check in case workflow key was already deleted
        return unless workflow_key && workflow_key_exists?(workflow_key)

        workflow_key
      end

      # Checks if a workflow key exists in Redis
      # @param workflow_key [String] the Redis key to check
      # @return [Boolean] true if the key exists
      def workflow_key_exists?(workflow_key)
        connection_pool.with do |redis|
          redis.exists?(workflow_key)
        end
      end
    end
  end
end
