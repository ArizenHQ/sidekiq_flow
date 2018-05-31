module SidekiqFlow
  class Task < Model
    attribute :start_time, (Types::Strict::Nil | Types::Strict::Integer).meta(omittable: true)
    attribute :end_time, Types::Strict::Integer.meta(omittable: true)
    attribute :execution_time, Types::Strict::Integer.meta(omittable: true)
    attribute :failed, Types::Strict::Bool.default(false)
    attribute :skipped, Types::Strict::Bool.default(false)
    attribute :loop_interval, Types::Strict::Integer.meta(omittable: true)
    attribute :retries, Types::Strict::Integer.default { SidekiqFlow.configuration.retries }
    attribute :job_id, Types::Strict::String.meta(omittable: true)
    attribute :queue, Types::Strict::String.default { SidekiqFlow.configuration.queue }
    attribute :children, Types::Strict::Array.of(Types::Strict::String).default([])
    attribute :params, Types::Strict::Hash.default({})

    def self.build(attrs={})
      attrs[:start_time] = Time.now.to_i unless attrs.has_key?(:start_time)
      new(attrs.reject { |k, v| read_only_attrs.include?(k) })
    end

    def self.read_only_attrs
      [:execution_time, :job_id, :failed, :skipped]
    end

    def self.permanent_attrs
      [
        :start_time, :end_time, :execution_time, :failed, :skipped,
        :loop_interval, :retries, :job_id, :queue, :children, :params
      ]
    end
  end
end
