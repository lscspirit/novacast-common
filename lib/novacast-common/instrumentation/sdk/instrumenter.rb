module Novacast
  module Instrumentation
    module SDK
      class Instrumenter
        def initialize(name, sdk_client)
          @name   = name
          @client = sdk_client
        end

        def method_missing(method, *args, &block)
          ActiveSupport::Notifications.instrument('api_call.novacast_sdk', sdk: @name, api: method) do
            @client.send method, *args, &block
          end
        end

        def respond_to_missing?(method, include_private = false)
          @client.respond_to_missing? method, include_private
        end
      end
    end
  end
end