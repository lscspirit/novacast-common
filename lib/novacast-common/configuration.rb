module Novacast
  # Novacast configurations
  #
  # @!attribute [rw] instrument_sdk
  #   @return [Boolean] whether to instrument Novacast sdk calls (default: true)
  class Configuration
    attr_accessor :instrument_sdk
    attr_accessor :instrument_rails_cache

    def initialize
      @instrument_sdk = true
      @instrument_rails_cache = true
    end
  end
end