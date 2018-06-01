module SidekiqFlow
  class Model < Dry::Struct
    def self.build(attrs={})
      new(attrs.reject { |k, v| read_only_attrs.include?(k) })
    end

    def self.read_only_attrs
      []
    end

    def self.permanent_attrs
      []
    end

    def self.from_hash(attrs)
      attrs[:class_name].constantize.new(attrs.reject { |k, v| v.nil? })
    end

    def class_name
      self.class.name
    end

    def to_json
      (self.class.permanent_attrs + [:class_name]).map { |a| [a, public_send(a)] }.to_h.to_json
    end
  end
end
