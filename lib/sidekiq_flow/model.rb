module SidekiqFlow
  class Model
    def self.attribute_names
      []
    end

    def self.build(klass, attrs)
      klass.constantize.new(attrs.deep_symbolize_keys)
    end

    def initialize(attrs={})
      self.class.attribute_names.each do |attr_name|
        class_eval { attr_reader attr_name }
      end
    end

    def klass
      self.class.to_s
    end

    def to_json
      self.class.attribute_names.map { |a| [a, public_send(a)] }.to_h.to_json
    end
  end
end
