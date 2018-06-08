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
        :start_date, :end_date, :loop_interval, :retries, :queue, :children,
        :status, :enqueued_at, :trigger_rule, :tasks_to_clear, :params, :job_id
      ]
    end

    def initialize(attrs={})
      super
      @start_date = attrs.fetch(:start_date, Time.now.to_i)
      @end_date = attrs[:end_date]
      @loop_interval = attrs[:loop_interval] || 0
      @retries = attrs[:retries] || SidekiqFlow.configuration.retries
      @queue = attrs[:queue] || SidekiqFlow.configuration.queue
      @children = attrs[:children] || []
      @status = attrs[:status] || STATUS_PENDING
      @enqueued_at = attrs[:enqueued_at]
      @trigger_rule = attrs[:trigger_rule] || 'all_succeeded'
      @tasks_to_clear = attrs[:tasks_to_clear] || []
      @params = attrs[:params] || {}
      @job_id = attrs[:job_id]
    end

    def perform
      raise NotImplementedError
    end

    def enqueue!(at=start_date)
      @status = STATUS_ENQUEUED
      @enqueued_at = at
    end

    def succeed!
      set_job!(nil)
      @status = STATUS_SUCCEEDED
    end

    def fail!
      set_job!(nil)
      @status = STATUS_FAILED
    end

    def skip!
      set_job!(nil)
      @status = STATUS_SKIPPED
    end

    def clear!
      @status = STATUS_PENDING
    end

    def await_retry!
      @status = STATUS_AWAITING_RETRY
    end

    def set_job!(job_id)
      @job_id = job_id
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

    def no_retries?
      retries == 0
    end

    def expired?
      end_date.present? && Time.now.to_i > end_date
    end

    def external_trigger?
      start_date.nil?
    end

    def has_job?
      job_id.present?
    end

    def ready_to_start?
      enqueued? && job_id.nil?
    end

    def set_workflow_params!(params)
      @workflow_params = params
    end

    private

    attr_reader :workflow_params
  end
end
