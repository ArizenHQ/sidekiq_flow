module SidekiqFlow
  class Model
    def self.attribute_names
      []
    end

    def self.build(klass, attrs)
      klass.constantize.new(attrs.deep_symbolize_keys)
    end

    def initialize(*args)
      self.class.attribute_names.each do |attr_name|
        class_eval do
          # Allow overloading
          attr_reader attr_name unless (instance_methods + private_instance_methods).include?(attr_name)
          attr_writer attr_name unless (instance_methods + private_instance_methods).include?(":#{attr_name}=")
        end
      end
    end

    def klass
      self.class.to_s
    end

    def to_h
      self.class.attribute_names.map { |a| [a, public_send(a)] }.to_h
    end

    def to_json
      to_h.to_json
    end

    def to_s
      klass.demodulize.underscore
    end
  end
end
