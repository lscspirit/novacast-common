require 'novacast-common/instrumentation/rails_cache/runtime_registry'

module Novacast
  module Instrumentation
    module RailsCache
      class LogSubscriber < ActiveSupport::LogSubscriber
        def self.runtime=(value)
          Novacast::Instrumentation::RailsCache::RuntimeRegistry.read_runtime = value
        end

        def self.runtime
          Novacast::Instrumentation::RailsCache::RuntimeRegistry.read_runtime ||= 0
        end

        def self.reset_runtime
          rt, self.runtime = runtime, 0
          rt
        end

        def cache_read(event)
          payload = event.payload

          # tracks the runtime duration for this call
          self.class.runtime += event.duration

          if payload[:super_operation] == :fetch
            name = 'Cache Fetch (%.1fms)' % [event.duration]
            debug "  #{color(name, YELLOW, true)} key: #{payload[:key]}"
          else
            name = 'Cache Read (%.1fms)' % [event.duration]
            debug "  #{color(name, YELLOW, true)} key: #{payload[:key]}, hit: #{payload[:hit]}"
          end
        end

        def cache_fetch_hit(event)
          payload = event.payload
          debug "  #{color('Cache Fetch Hit', YELLOW, true)} key: #{payload[:key]}"
        end
      end
    end
  end
end