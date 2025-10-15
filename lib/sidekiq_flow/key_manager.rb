module SidekiqFlow
  # Manages Redis key generation, lookup, and storage for workflows
  class KeyManager
    attr_reader :connection_pool, :configuration

    def initialize(connection_pool, configuration)
      @connection_pool = connection_pool
      @configuration = configuration
    end

    # Creates the initial Redis key for a new workflow and stores it in the lookup hash
    # @param workflow_id [String, Integer] the workflow identifier
    # @param timestamp [Integer] the Unix timestamp
    # @param redis [Redis, nil] optional Redis connection (avoids nested pool usage)
    # @return [String] the generated workflow key
    def generate_initial_workflow_key(workflow_id, timestamp, redis = nil)
      workflow_key = "#{configuration.namespace}.#{workflow_id}_#{timestamp}_0"
      store_workflow_key(workflow_id, workflow_key, redis)
      workflow_key
    end

    # Looks up the Redis key for a workflow using the lookup hash with fallback to legacy method
    # @param workflow_id [String, Integer] the workflow identifier
    # @param redis [Redis, nil] optional Redis connection (avoids nested pool usage)
    # @return [String, nil] the Redis key or nil if not found
    def find_workflow_key(workflow_id, redis = nil)
      # Try new lookup hash first
      workflow_key = lookup_workflow_key(workflow_id, redis)
      return workflow_key if workflow_key.present?

      # Fallback to old timestamp-based lookup for existing workflows
      workflow_key = build_workflow_key_from_timestamps(workflow_id, redis)

      # If found via fallback, migrate it to the new lookup hash
      if workflow_key.present?
        store_workflow_key(workflow_id, workflow_key, redis)
      end

      workflow_key
    end

    # Retrieves a workflow key from the lookup hash
    # @param workflow_id [String, Integer] the workflow identifier
    # @param redis [Redis, nil] optional Redis connection (avoids nested pool usage)
    # @return [String, nil] the workflow key or nil if not found
    def lookup_workflow_key(workflow_id, redis = nil)
      if redis
        redis.hget(workflow_keys_namespace, workflow_id)
      else
        connection_pool.with do |conn|
          conn.hget(workflow_keys_namespace, workflow_id)
        end
      end
    end

    # Stores a workflow key in the lookup hash for fast retrieval
    # @param workflow_id [String, Integer] the workflow identifier
    # @param workflow_key [String] the Redis key to store
    # @param redis [Redis, nil] optional Redis connection (avoids nested pool usage)
    # @return [void]
    def store_workflow_key(workflow_id, workflow_key, redis = nil)
      if redis
        redis.hset(workflow_keys_namespace, workflow_id, workflow_key)
      else
        connection_pool.with do |conn|
          conn.hset(workflow_keys_namespace, workflow_id, workflow_key)
        end
      end
    end

    # Removes a workflow key from the lookup hash
    # @param workflow_id [String, Integer] the workflow identifier
    # @param redis [Redis, nil] optional Redis connection (avoids nested pool usage)
    # @return [void]
    def delete_workflow_key(workflow_id, redis = nil)
      if redis
        redis.hdel(workflow_keys_namespace, workflow_id)
      else
        connection_pool.with do |conn|
          conn.hdel(workflow_keys_namespace, workflow_id)
        end
      end
    end

    # Legacy method that rebuilds a workflow key from timestamp keys (fallback for old workflows)
    # @param workflow_id [String, Integer] the workflow identifier
    # @param redis [Redis, nil] optional Redis connection (avoids nested pool usage)
    # @return [String, nil] the reconstructed workflow key or nil if timestamps missing
    def build_workflow_key_from_timestamps(workflow_id, redis = nil)
      start_timestamp, end_timestamp = if redis
                                         redis.pipelined do |pipeline|
                                           pipeline.get("#{timestamp_namespace}.#{workflow_id}.start")
                                           pipeline.get("#{timestamp_namespace}.#{workflow_id}.end")
                                         end
                                       else
                                         connection_pool.with do |conn|
                                           conn.pipelined do |pipeline|
                                             pipeline.get("#{timestamp_namespace}.#{workflow_id}.start")
                                             pipeline.get("#{timestamp_namespace}.#{workflow_id}.end")
                                           end
                                         end
                                       end

      return nil unless start_timestamp

      workflow_key = if end_timestamp && start_timestamp
                       "#{configuration.namespace}.#{workflow_id}_#{start_timestamp}_#{end_timestamp}"
                     elsif start_timestamp
                       "#{configuration.namespace}.#{workflow_id}_#{start_timestamp}_0"
                     end

      # Verify the workflow data actually exists
      unless workflow_key_exists?(workflow_key, redis)
        configuration.logger.warn("Workflow[#{workflow_id}] Timestamps exist but workflow data missing (key: #{workflow_key})")
        return nil
      end

      workflow_key
    end

    # Checks if a workflow key exists in Redis
    # @param workflow_key [String] the Redis key to check
    # @param redis [Redis, nil] optional Redis connection (avoids nested pool usage)
    # @return [Boolean] true if the key exists
    def workflow_key_exists?(workflow_key, redis = nil)
      if redis
        redis.exists?(workflow_key)
      else
        connection_pool.with do |conn|
          conn.exists?(workflow_key)
        end
      end
    end

    # Returns the Redis namespace for the workflow key lookup hash
    # @return [String] the workflow keys namespace
    def workflow_keys_namespace
      'workflow-keys'
    end

    # Returns the Redis namespace for workflow timestamp keys
    # @return [String] the timestamp namespace
    def timestamp_namespace
      'workflow-timestamps'
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
  end
end
