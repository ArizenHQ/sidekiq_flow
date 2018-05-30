module SidekiqFlow
  class Model < Dry::Struct
    def self.permanent_attrs
      []
    end

    def klass
      self.class
    end

    def to_json
      JSON.generate((self.class.permanent_attrs + [:klass]).map { |a| [a, public_send(a)] }.to_h)
    end
  end
end
