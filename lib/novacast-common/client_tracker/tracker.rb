require 'novacast-common/client_tracker/user_count'
require 'novacast-common/client_tracker/config'

module Novacast
  module ClientTracker
    module Tracker
      #
      # Keys
      #

      EVENT_LIST_KEY         = 'tracker:event-list'
      EVENT_SESSION_KEY      = 'tracker:session'
      EVENT_SESSION_TIME_KEY = 'tracker:session-time'
      EVENT_USER_KEY         = 'tracker:event-user'
      SESSION_USER_KEY       = 'tracker:session-user'
      USER_SESSION_TIME_KEY  = 'tracker:user-session-time'
      SESSION_USER_ONLINE_KEY = 'tracker:session-user-online'
      SESSION_USER_OFFLINE_KEY = 'tracker:session-user-offline'

      #
      # Configuration
      #

      def self.configure
        yield self.config if block_given?
        self.config.validate!
      end

      #
      # Public Methods
      #

      def self.track_user(user_uid, event_uid, session_uid)
        time_now = self._server_time

        # adds an entry to the event-user, session-user and user-session mapping sets
        event_user_code   = _event_user_code(user_uid, event_uid)
        session_user_code = _session_user_code(user_uid, session_uid)
        user_session_code = _user_session_code(user_uid, event_uid, session_uid)

        #keep track of new onlines when a user first send in the heartbeat
        score = redis.zscore SESSION_USER_KEY, session_user_code
        if score.nil?
          redis.sadd SESSION_USER_ONLINE_KEY, session_user_code
        end

        redis.multi do |multi|
          # adds the event uid to the main event list
          multi.zadd EVENT_LIST_KEY, time_now, event_uid

          # adds an entry to the event-session mapping sets
          event_session_code = _event_session_code(event_uid, session_uid)
          multi.zadd EVENT_SESSION_KEY, 0, event_session_code
          multi.zadd EVENT_SESSION_TIME_KEY, time_now, event_session_code

          multi.zadd EVENT_USER_KEY, 0, event_user_code
          multi.zadd SESSION_USER_KEY, 0, session_user_code
          multi.zadd USER_SESSION_TIME_KEY, time_now, user_session_code
        end
      end

      def self.active_events
        redis.watch EVENT_LIST_KEY do
          now = self._server_time

          redis.multi do |multi|
            # purges expired events
            multi.zremrangebyscore EVENT_LIST_KEY, 0, (now - self.config.event_ttl)
          end

          # returns all remaining events
          redis.zrange(EVENT_LIST_KEY, 0, -1)
        end
      end

      def self.all_event_sessions
        # purges the event-session mapping
        _purge_event_sessions

        # gets all event-session entries from the key
        codes = redis.zrange(EVENT_SESSION_KEY, 0, -1)
        # parses the code the get the actual session uid
        codes.map { |c| _parse_event_session_code(c)[:session_uid] }
      end

      def self.event_sessions(event_uid)
        # purges the event-session mapping
        _purge_event_sessions

        # gets all event-session entries with the event_uid as prefix
        codes = redis.zrangebylex(EVENT_SESSION_KEY, "[#{event_uid}:", "[#{event_uid}:\xff")
        # parses the code the get the actual session uid
        codes.map { |c| _parse_event_session_code(c)[:session_uid] }
      end

      def self.all_user_count
        # purges expired user and event-session mappings
        _purge_event_sessions
        _purge_users

        event_uids = active_events

        # gets the complete event-session mappings
        session_event_map = {}
        redis.zscan_each EVENT_SESSION_KEY do |(code, score)|
          uids = _parse_event_session_code code
          session_event_map[uids[:session_uid]] = uids[:event_uid]
        end if redis.exists EVENT_SESSION_KEY

        # gets the per-event user counts
        event_user_counter = Hash.new { 0 }
        redis.zscan_each EVENT_USER_KEY do |(code, score)|
          uids = _parse_event_user_code code
          event_user_counter[uids[:event_uid]] += 1
        end if redis.exists EVENT_USER_KEY

        # gets the per-session user counts
        session_user_counter = Hash.new { 0 }
        redis.zscan_each SESSION_USER_KEY do |(code, score)|
          uids = _parse_session_user_code code
          session_user_counter[uids[:session_uid]] += 1
        end if redis.exists SESSION_USER_KEY


        # creates a UserCount instance for each session
        event_session_counter = Hash.new { |h, k| h[k] = {} }
        session_event_map.each do |session_uid, event_uid|
          count = session_user_counter[session_uid] || 0
          event_session_counter[event_uid][session_uid] = UserCount.new count
        end

        # groups all UserCounts into its own EventUserCount instance
        event_uids.reduce({}) do |h, event_uid|
          count = event_user_counter[event_uid] || 0
          session_counts = event_session_counter[event_uid] || {}
          h[event_uid] = EventUserCount.new count, session_counts
          h
        end
      end

      def self.event_users(event_uid)
        # purges expired user entries from related mappings
        _purge_users

        # gets all the event-user entries with the event_uid as prefix
        codes = redis.zrangebylex EVENT_USER_KEY, "[#{event_uid}:", "[#{event_uid}:\xff"
        codes.map { |c| _parse_event_user_code(c)[:user_uid] }
      end

      def self.event_user_count(event_uid)
        # purges expired user entries from related mappings
        _purge_users

        redis.zlexcount EVENT_USER_KEY, "[#{event_uid}:", "[#{event_uid}:\xff"
      end

      def self.session_users(session_uid)
        # purges expired user entries from related mappings
        _purge_users

        # gets all the session-user entries with the session_uid as prefix
        codes = redis.zrangebylex SESSION_USER_KEY, "[#{session_uid}:", "[#{session_uid}:\xff"
        codes.map { |c| _parse_session_user_code(c)[:user_uid] }
      end

      def self.session_user_count(session_uid)
        # purges expired user entries from related mappings
        _purge_users

        redis.zlexcount SESSION_USER_KEY, "[#{session_uid}:", "[#{session_uid}:\xff"
      end

      def self.all_user_status_updates(clear = false)
        ret = Hash.new {|hsh, k| hsh[k] = Hash.new {|hsh2, k2| hsh2[k2] = []}}
        new_onlines = redis.smembers SESSION_USER_ONLINE_KEY || []
        new_offlines = redis.smembers SESSION_USER_OFFLINE_KEY || []
        if clear
          redis.del SESSION_USER_ONLINE_KEY
          redis.del SESSION_USER_OFFLINE_KEY
        end

        new_onlines.each do |session_user|
          su = _parse_session_user_code(session_user)
          ret[su[:session_uid]][:onlines] << su[:user_uid]
        end

        new_offlines.each do |session_user|
          su = _parse_session_user_code(session_user)
          ret[su[:session_uid]][:offlines] << su[:user_uid]
        end

        ret
      end

      #
      # Private Methods
      #

      private

      def self.config
        @config ||= Config.new
      end

      def self.redis
        self.config.redis
      end

      def self._server_time
        redis.time[0]
      end

      def self._purge_event_sessions(now = self._server_time)
        sess_active_ttl = self.config.session_ttl

        redis.watch [EVENT_SESSION_KEY, EVENT_SESSION_TIME_KEY] do
          # gets a list of expired event-session entries to be purged
          purge_list = redis.zrangebyscore EVENT_SESSION_TIME_KEY, 0, (now.to_i - sess_active_ttl)

          redis.multi do |multi|
            # purges expried event-session from the time-sorted list
            multi.zremrangebyscore EVENT_SESSION_TIME_KEY, 0, (now.to_i - sess_active_ttl)
            # purges event-session from the overall list
            multi.zrem EVENT_SESSION_KEY, purge_list unless purge_list.empty?
          end
        end
      end

      def self._purge_users(now = self._server_time)
        user_active_ttl = self.config.user_ttl

        redis.watch [EVENT_USER_KEY, SESSION_USER_KEY, USER_SESSION_TIME_KEY] do
          # gets a list of users to be purged
          purge_list = redis.zrangebyscore USER_SESSION_TIME_KEY, 0, (now.to_i - user_active_ttl)
          event_user_purge_list   = Set.new
          session_user_purge_list = []

          # generates codes for the different lists
          purge_list.each do |code|
            uids = _parse_user_session_code(code)
            event_user_purge_list   << _event_user_code(uids[:user_uid], uids[:event_uid])
            session_user_purge_list << _session_user_code(uids[:user_uid], uids[:session_uid])
          end

          redis.multi do |multi|
            # purges the users from the time-sorted user list
            multi.zremrangebyscore USER_SESSION_TIME_KEY, 0, (now.to_i - user_active_ttl)
            # purges the event-user entries
            multi.zrem EVENT_USER_KEY, event_user_purge_list.to_a unless event_user_purge_list.empty?
            # purges the session-user entries
            multi.zrem SESSION_USER_KEY, session_user_purge_list unless session_user_purge_list.empty?
            #record the newly offlines
            multi.sadd SESSION_USER_OFFLINE_KEY, session_user_purge_list.to_a unless session_user_purge_list.empty?
          end
        end
      end

      #
      # Code
      #

      def self._event_session_code(event_uid, session_uid)
        "#{event_uid}:#{session_uid}"
      end

      def self._parse_event_session_code(code)
        uids = code.split(':')
        { event_uid: uids[0], session_uid: uids[1] }
      end

      def self._event_user_code(user_uid, event_uid)
        "#{event_uid}:#{user_uid}"
      end

      def self._parse_event_user_code(code)
        uids = code.split(':')
        { event_uid: uids[0], user_uid: uids[1] }
      end

      def self._session_user_code(user_uid, session_uid)
        "#{session_uid}:#{user_uid}"
      end

      def self._parse_session_user_code(code)
        uids = code.split(':')
        { session_uid: uids[0], user_uid: uids[1] }
      end

      def self._user_session_code(user_uid, event_uid, session_uid)
        "#{user_uid}:#{event_uid}:#{session_uid}"
      end

      def self._parse_user_session_code(code)
        uids = code.split(':')
        { user_uid: uids[0], event_uid: uids[1], session_uid: uids[2] }
      end
    end
  end
end