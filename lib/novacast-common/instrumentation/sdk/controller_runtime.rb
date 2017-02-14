module Novacast
  module Instrumentation
    module SDK
      module ControllerRuntime
        extend ActiveSupport::Concern

        protected

        attr_internal :novacast_sdk_runtime_before_render
        attr_internal :novacast_sdk_runtime_during_render

        def cleanup_view_runtime
          self.novacast_sdk_runtime_before_render = Novacast::Instrumentation::SDK::LogSubscriber.reset_runtime
          runtime = super
          self.novacast_sdk_runtime_during_render = Novacast::Instrumentation::SDK::LogSubscriber.reset_runtime
          runtime - novacast_sdk_runtime_during_render
        end

        def append_info_to_payload(payload)
          super
          payload[:novacast_sdk_runtime] = (novacast_sdk_runtime_before_render || 0) +
                                           (novacast_sdk_runtime_during_render || 0) +
                                           Novacast::Instrumentation::SDK::LogSubscriber.reset_runtime
        end

        module ClassMethods
          def log_process_action(payload)
            messages, sdk_runtime = super, payload[:novacast_sdk_runtime]
            messages << ("NovacastSDK: %.1fms" % sdk_runtime.to_f) if sdk_runtime
            messages
          end
        end
      end
    end
  end
end