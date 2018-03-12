require 'rails'

require 'novacast-common/instrumentation/sdk/instrumenter'
require 'novacast-common/instrumentation/sdk/log_subscriber'
require 'novacast-common/instrumentation/sdk/controller_runtime'

require 'novacast-common/instrumentation/rails_cache/log_subscriber'
require 'novacast-common/instrumentation/rails_cache/controller_runtime'

module Novacast
  module Instrumentation
    class Railtie < Rails::Railtie
      initializer 'instrumentation.novacast' do
        # only enable instrumentation when 'instrument_sdk' is true
        if Novacast.config.instrument_sdk
          Novacast::Instrumentation::SDK::LogSubscriber.attach_to :novacast_sdk

          ActiveSupport.on_load(:action_controller) do
            include Novacast::Instrumentation::SDK::ControllerRuntime
          end
        end
      end

      initializer 'instrumentation.rails_cache' do
        # only enable instrumentation when 'instrument_rails_cache' is true
        if Novacast.config.instrument_rails_cache
          Novacast::Instrumentation::RailsCache::LogSubscriber.attach_to :active_support

          ActiveSupport.on_load(:action_controller) do
            include Novacast::Instrumentation::RailsCache::ControllerRuntime
          end
        end
      end
    end
  end
end