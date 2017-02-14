module Novacast
  # Novacast configurations
  #
  # @!attribute [rw] instrument_sdk
  #   @return [Boolean] whether to instrument Novacast sdk calls (default: true)
  class Configuration
    attr_accessor :instrument_sdk

    def initialize
      @instrument_sdk = true
    end
  end
end