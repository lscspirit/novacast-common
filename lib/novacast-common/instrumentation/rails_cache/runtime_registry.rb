module Novacast
  module Instrumentation
    module RailsCache
      class RuntimeRegistry
        extend ActiveSupport::PerThreadRegistry

        attr_accessor :read_runtime
      end
    end
  end
end