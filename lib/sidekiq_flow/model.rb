module SidekiqFlow
  class Model < Dry::Struct
    def self.build(attrs)
      new(attrs.reject { |k, v| v.nil? || read_only_attrs.include?(k) })
    end

    def self.read_only_attrs
      []
    end

    def self.from_json(json)
      attrs = JSON.parse(json, symbolize_names: true)
      ActiveSupport::Inflector.constantize(attrs[:class_name]).build(attrs)
    end

    def class_name
      self.class.name
    end

    def to_json
      (self.class.attribute_names + [:class_name]).map { |a| [a, public_send(a)] }.to_h.to_json
    end
  end
end
