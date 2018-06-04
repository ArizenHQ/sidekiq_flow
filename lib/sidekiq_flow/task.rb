module SidekiqFlow
  class Task < Model
    STATUS_PENDING = 'pending'
    STATUS_ENQUEUED = 'enqueued'
    STATUS_SUCCEEDED = 'succeeded'
    STATUS_FAILED = 'failed'
    STATUS_SKIPPED = 'skipped'
    STATUS_AWAITING_RETRY = 'awaiting_retry'

    def self.attribute_names
      [
        :start_date, :end_date, :loop_interval, :retries, :job_id, :queue,
        :children, :tasks_to_clear, :status, :enqueued_at, :trigger_rule, :params
      ]
    end

    def initialize(attrs={})
      super
      @start_date = attrs.fetch(:start_date, Time.now.to_i)
      @end_date = attrs[:end_date]
      @loop_interval = attrs[:loop_interval] || 0
      @retries = attrs[:retries] || SidekiqFlow.configuration.retries
      @job_id = attrs[:job_id]
      @queue = attrs[:queue] || SidekiqFlow.configuration.queue
      @children = attrs[:children] || []
      @tasks_to_clear = attrs[:tasks_to_clear] || []
      @status = attrs[:status] || STATUS_PENDING
      @enqueued_at = attrs[:enqueued_at]
      @trigger_rule = attrs[:trigger_rule] || 'all_succeeded'
      @params = attrs[:params] || {}
    end

    def perform
      raise NotImplementedError
    end

    def enqueue!(at=start_date)
      @status = STATUS_ENQUEUED
      @enqueued_at = at
    end

    def succeed!
      @status = STATUS_SUCCEEDED
    end

    def fail!
      @status = STATUS_FAILED
    end

    def skip!
      @status = STATUS_SKIPPED
    end

    def clear!
      @status = STATUS_PENDING
    end

    def await_retry!
      @status = STATUS_AWAITING_RETRY
    end

    def enqueued?
      @status == STATUS_ENQUEUED
    end

    def succeeded?
      @status == STATUS_SUCCEEDED
    end

    def failed?
      @status == STATUS_FAILED
    end

    def skipped?
      @status == STATUS_SKIPPED
    end

    def pending?
      @status == STATUS_PENDING
    end

    def awaiting_retry?
      @status == STATUS_AWAITING_RETRY
    end

    def set_job!(job_id)
      @job_id = job_id
    end

    def no_retries?
      retries == 0
    end

    def expired?
      end_date.present? && Time.now > end_date
    end

    def external_trigger?
      start_date.nil?
    end
  end
end
