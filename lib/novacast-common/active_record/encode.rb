module Novacast
  module ActiveRecord
    module Encode
      extend ActiveSupport::Concern

      def encode_record(record)
        self.class.encode_record(record)
      end

      def allocate_record(klass, coder)
        self.class.allocate_record klass, coder
      end

      class_methods do
        # Encode an ActiveRecord object into a coder using ActiveRecord::Base#encode_with
        #
        # @param [ActiveRecord::Base] active record object
        #
        # @return [Hash, nil] encoded coder; nil if record is nil
        def encode_record(record)
          return nil if record.nil?
          raise ArgumentError, 'record must be an ActiveRecord' unless record.is_a?(::ActiveRecord::Base)

          coder = {}
          record.encode_with(coder)
          coder
        end

        # Initialize an ActiveRecord object with the provided coder
        #
        # @param [Class] class of the object
        # @param [Hash] coder
        #
        # @return [Object, nil] the allocated object; nil if coder is nil
        def allocate_record(klass, coder)
          return nil if coder.nil?

          inst = klass.allocate
          inst.init_with(coder)
          inst
        end
      end
    end
  end
end