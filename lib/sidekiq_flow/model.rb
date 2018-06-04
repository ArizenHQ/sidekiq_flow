module SidekiqFlow
  class Model
    def self.attribute_names
      []
    end

    def self.from_hash(attrs={})
      attrs[:klass].constantize.new(attrs)
    end

    def initialize(attrs={})
      self.class.attribute_names.each do |attr_name|
        class_eval { attr_reader attr_name }
      end
    end

    def klass
      self.class.to_s
    end

    def to_h
      (self.class.attribute_names + [:klass]).map { |a| [a, public_send(a)] }.to_h
    end
  end
end
