require 'rails'

require 'novacast-common/logging/formatter'

module Novacast
  module Logging
    class Railtie < Rails::Railtie
      config.before_initialize do
        # extends the current log formatter with Novacast custom format
        Rails.logger.formatter = Novacast::Logging::Formatter.new
      end
    end
  end
end