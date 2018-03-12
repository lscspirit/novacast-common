module Novacast
  module Instrumentation
    module RailsCache
      module ControllerRuntime
        extend ActiveSupport::Concern

        protected

        attr_internal :cache_runtime_before_render
        attr_internal :cache_runtime_during_render

        def cleanup_view_runtime
          self.cache_runtime_before_render = Novacast::Instrumentation::RailsCache::LogSubscriber.reset_runtime
          runtime = super
          self.cache_runtime_during_render = Novacast::Instrumentation::RailsCache::LogSubscriber.reset_runtime
          runtime - cache_runtime_during_render
        end

        def append_info_to_payload(payload)
          super
          payload[:cache_read_runtime] = (cache_runtime_before_render || 0) +
                                         (cache_runtime_during_render || 0) +
                                         Novacast::Instrumentation::RailsCache::LogSubscriber.reset_runtime
        end

        module ClassMethods
          def log_process_action(payload)
            messages, read_runtime = super, payload[:cache_read_runtime]
            messages << ("Cache: %.1fms" % read_runtime.to_f) if read_runtime
            messages
          end
        end
      end
    end
  end
end