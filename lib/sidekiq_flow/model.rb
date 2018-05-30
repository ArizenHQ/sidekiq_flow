module SidekiqFlow
  class Model < Dry::Struct
    private_class_method :new

    def self.build(attrs)
      new(attrs.reject { |k, v| v.nil? || read_only_attrs.include?(k) })
    end

    def self.read_only_attrs
      []
    end

    def self.permanent_attrs
      []
    end

    def self.from_json(json)
      attrs = JSON.parse(json, symbolize_names: true)
      ActiveSupport::Inflector.constantize(attrs[:klass]).build(attrs)
    end

    def klass
      self.class
    end

    def to_json
      (self.class.permanent_attrs + [:klass]).map { |a| [a, public_send(a)] }.to_h.to_json
    end
  end
end
