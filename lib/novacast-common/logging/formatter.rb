module Novacast
  module Logging
    class Formatter < ActiveSupport::Logger::SimpleFormatter
      include ActiveSupport::TaggedLogging::Formatter

      ENTRY_FORMAT    = "%s (#%d - %s)%s %5s -- %s\n"
      DATETIME_FORMAT = '%Y-%m-%dT%T.%L%z'.freeze

      def call(severity, time, progname, msg)
        tags_str = (tags = tags_text).blank? ? '' : " #{tags}"
        ENTRY_FORMAT % [format_datetime(time), $$, Thread.current.object_id, tags_str, severity, msg2str(msg)]
      end

      private

      def format_datetime(time)
        time.strftime(DATETIME_FORMAT)
      end
    end
  end
end