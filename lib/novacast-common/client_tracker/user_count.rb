module Novacast
  module ClientTracker
    class UserCount
      attr_reader :user_count

      def initialize(count)
        @user_count = count
      end
    end

    class EventUserCount < UserCount
      def initialize(count, session_counts = nil)
        super(count)
        @session_counts = session_counts || {}
      end

      def [](session_uid)
        @session_counts[session_uid]
      end

      def session_uids
        @session_counts.keys
      end

      def each(&block)
        @session_counts.each(&block)
      end
    end
  end
end