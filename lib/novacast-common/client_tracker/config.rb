module Novacast
  module ClientTracker
    class Config
      attr_accessor :redis, :event_ttl, :session_ttl, :user_ttl

      def initialize
        @redis = nil
        @event_ttl   = 300
        @session_ttl = 300
        @user_ttl = 60
      end

      def validate!
        raise RuntimeError, 'must provide an Redis instance' if @redis.nil?
        raise RuntimeError, 'session ttl must be smaller than or equal to event ttl' unless @session_ttl <= @event_ttl
        raise RuntimeError, 'user ttl must be smaller than or equal to session ttl' unless @user_ttl <= @session_ttl
      end

      def redis=(r)
        raise ArgumentError, 'must be a Redis or ConnectionPool instance' if r.nil?

        @redis = if r.is_a?(::ConnectionPool)
          r
        else
          ::ConnectionPool.new(size: 10, timeout: 5) { r }
        end
      end
    end
  end
end