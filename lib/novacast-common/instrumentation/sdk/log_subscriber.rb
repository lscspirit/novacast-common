require 'novacast-common/instrumentation/sdk/runtime_registry'

module Novacast
  module Instrumentation
    module SDK
      class LogSubscriber < ActiveSupport::LogSubscriber
        def self.runtime=(value)
          Novacast::Instrumentation::SDK::RuntimeRegistry.api_runtime = value
        end

        def self.runtime
          Novacast::Instrumentation::SDK::RuntimeRegistry.api_runtime ||= 0
        end

        def self.reset_runtime
          rt, self.runtime = runtime, 0
          rt
        end

        def api_call(event)
          payload = event.payload

          # tracks the runtime duration for this call
          self.class.runtime += event.duration

          name = '%s API Call (%.1fms)' % [payload[:sdk], event.duration]
          debug "  #{color(name, YELLOW, true)} api: #{payload[:api]}"
        end
      end
    end
  end
end