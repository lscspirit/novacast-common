module Novacast
  module Instrumentation
    module SDK
      class RuntimeRegistry
        extend ActiveSupport::PerThreadRegistry

        attr_accessor :api_runtime
      end
    end
  end
end