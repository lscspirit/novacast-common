require 'novacast-common/configuration'
require 'novacast-common/logging/railtie'
require 'novacast-common/instrumentation/railtie'
require 'novacast-common/client_tracker/tracker'

module Novacast
  class << self
    attr_writer :config
  end

  # Novacast configuration
  #
  # @return [Novacast::Configuration] the config object
  def self.config
    @config ||= Novacast::Configuration.new
  end

  # Configures the gem
  #
  # @example
  #   Novacast.configure do |config|
  #     config.instrument_sdk = false
  #   end
  def self.configure
    yield self.config
  end
end