require 'connection_pool'

RSpec.describe Novacast::ClientTracker::Tracker do
  let(:redis) { Redis.new }
  let(:current_time) { Time.now }

  let(:event_ttl) { rand(100..300) }
  let(:session_ttl) { rand(100..event_ttl) }
  let(:user_ttl) { rand(100..session_ttl) }

  #
  # Events
  #

  let(:event_uids) { rand(2..10).times.map { Faker::Lorem::characters(15) } }
  let(:main_event_uids) do
    count = rand(1..(event_uids.count - 1))  # leaves at least one uid to be put in the secondary list
    event_uids.sample(count)
  end
  let(:sec_event_uids) { event_uids - main_event_uids }

  #
  # Sessions
  #

  let(:session_uids) { rand(event_uids.count..(event_uids.count * 5)).times.map { Faker::Lorem.characters(15) } }
  let(:main_session_uids) do
    count = rand(1..(session_uids.count - 1)) # leaves at least one uid to be put in the secondary list
    session_uids.sample(count)
  end
  let(:sec_session_uids) { session_uids - main_session_uids }
  let(:session_event_map) do
    # randomly associates the session uid to an event uid
    session_uids.reduce({}) { |h, uid| h[uid] = event_uids.sample; h }
  end

  #
  # User Sessions
  #

  let(:user_uids) { rand(5..30).times.map { Faker::Lorem.characters(15) } }
  let(:main_user_uids) do
    count = rand(1..(user_uids.count - 1)) # leaves at least one uid to be put in the secondary list
    user_uids.sample(count)
  end
  let(:sec_user_uids) { user_uids - main_user_uids }
  let(:user_session_map) do
    max_num_session = [session_uids.count, 4].max
    user_uids.reduce({}) { |h, user_uid| h[user_uid] = session_uids.sample(rand(1..max_num_session)); h }
  end

  #
  # Helper Methods
  #

  def event_session_code(event_uid, session_uid)
    "#{event_uid}:#{session_uid}"
  end

  def event_user_code(user_uid, event_uid)
    "#{event_uid}:#{user_uid}"
  end

  def session_user_code(user_uid, session_uid)
    "#{session_uid}:#{user_uid}"
  end

  def user_session_code(user_uid, event_uid, session_uid)
    "#{user_uid}:#{event_uid}:#{session_uid}"
  end

  def add_events_to_cache(event_list, expired = false)
    current = current_time.to_i
    age = expired ?
      rand(event_ttl...(event_ttl * 5)) :
      rand(0...event_ttl)

    # adds event uids to the list with active timestamps
    redis.multi do |multi|
      event_list.each do |uid|
        multi.zadd Novacast::ClientTracker::Tracker::EVENT_LIST_KEY, current - age, uid
      end
    end
  end

  def add_sessions_to_cache(session_list, expired = false)
    current = current_time.to_i
    age = expired ?
      rand(session_ttl...(session_ttl * 5)) :
      rand(0...session_ttl)

    # adds event uids to the list with active timestamps
    redis.multi do |multi|
      session_list.each do |uid|
        code = event_session_code(session_event_map[uid], uid)
        multi.zadd Novacast::ClientTracker::Tracker::EVENT_SESSION_KEY, 0, code
        multi.zadd Novacast::ClientTracker::Tracker::EVENT_SESSION_TIME_KEY, current - age, code
      end
    end
  end

  def add_users_to_cache(users_list, expired = false)
    current = current_time.to_i
    age = expired ?
      rand(user_ttl...(user_ttl * 5)) :
      rand(0...user_ttl)

    # adds event uids to the list with active timestamps
    redis.multi do |multi|
      users_list.each do |user_uid|
        user_session_map[user_uid].each do |session_uid|
          event_uid = session_event_map[session_uid]

          multi.zadd Novacast::ClientTracker::Tracker::EVENT_USER_KEY, 0, event_user_code(user_uid, event_uid)
          multi.zadd Novacast::ClientTracker::Tracker::SESSION_USER_KEY, 0, session_user_code(user_uid, session_uid)
          multi.zadd Novacast::ClientTracker::Tracker::USER_SESSION_TIME_KEY, current - age, user_session_code(user_uid, event_uid, session_uid)
        end
      end
    end
  end

  def users_for_event(event_uid, user_list)
    # finds all session uids for this event
    sess_uids = session_event_map.select { |sess_uid, evt_uid| evt_uid == event_uid }.keys
    # finds all users in these sessions
    user_session_map.select do |user_uid, user_sess_uids|
      # selects only active users and users the belongs to the sessions
      user_list.include?(user_uid) && !(user_sess_uids & sess_uids).empty?
    end
  end

  def users_for_session(session_uid, user_list)
    # finds all users in this session
    user_session_map.select do |user_uid, user_sess_uids|
      # selects only active users and users the belongs to the sessions
      user_list.include?(user_uid) && user_sess_uids.include?(session_uid)
    end
  end

  #
  # Setup
  #

  before :example do
    Novacast::ClientTracker::Tracker.configure do |config|
      config.redis = redis
      config.event_ttl   = event_ttl
      config.session_ttl = session_ttl
      config.user_ttl    = user_ttl
    end

    # FIXME: polyfill zlexcount because fakeredis does not support this command
    redis.define_singleton_method(:zlexcount) do |key, min, max|
      result = self.zrangebylex key, min, max
      result.size
    end
  end

  describe '::track_user' do
    # stub the redis client
    let(:redis) { spy('redis_client') }

    let(:user_uid)    { Faker::Lorem::characters(15) }
    let(:event_uid)   { Faker::Lorem::characters(15) }
    let(:session_uid) { Faker::Lorem::characters(15) }

    before :example do
      allow(redis).to receive(:multi).and_yield(redis)
      allow(redis).to receive(:zadd)
      allow(redis).to receive(:time).and_return([current_time.to_i, 0])

      Novacast::ClientTracker::Tracker.track_user user_uid, event_uid, session_uid
    end

    it 'adds the event uid to the event list' do
      expect(redis).to have_received(:zadd).with(Novacast::ClientTracker::Tracker::EVENT_LIST_KEY, current_time.to_i, event_uid).once
    end

    it 'adds the session entry to the overall event session list' do
      expect(redis).to have_received(:zadd).with(Novacast::ClientTracker::Tracker::EVENT_SESSION_KEY, 0, event_session_code(event_uid, session_uid)).once
    end

    it 'adds the session entry to the time-sorted event session list' do
      expect(redis).to have_received(:zadd).with(Novacast::ClientTracker::Tracker::EVENT_SESSION_TIME_KEY, current_time.to_i, event_session_code(event_uid, session_uid)).once
    end

    it 'adds the user to the user-event list' do
      expect(redis).to have_received(:zadd).with(Novacast::ClientTracker::Tracker::EVENT_USER_KEY, 0, event_user_code(user_uid, event_uid)).once
    end

    it 'adds the user session entry to the overall user session list' do
      expect(redis).to have_received(:zadd).with(Novacast::ClientTracker::Tracker::SESSION_USER_KEY, 0, session_user_code(user_uid, session_uid)).once
    end

    it 'adds the user session entry to the time-sorted user session list' do
      expect(redis).to have_received(:zadd).with(Novacast::ClientTracker::Tracker::USER_SESSION_TIME_KEY, current_time.to_i, user_session_code(user_uid, event_uid, session_uid)).once
    end
  end

  describe '::active_events' do
    subject { Novacast::ClientTracker::Tracker.active_events }

    context 'with no existing entries' do
      it 'returns an empty list' do
        expect(subject).to be_empty
      end
    end

    context 'with active entries only' do
      before :example do
        add_events_to_cache(main_event_uids)
      end

      it 'returns all active event uids' do
        expect(subject).to match_array(main_event_uids)
      end
    end

    context 'with inactive entries only' do
      before :example do
        add_events_to_cache(main_event_uids, true)
      end

      it 'returns an empty list' do
        expect(subject).to be_empty
      end
    end

    context 'with active and inactive entries' do
      before :example do
        add_events_to_cache(main_event_uids)
        add_events_to_cache(sec_event_uids, true)
      end

      it 'returns only active event uids' do
        expect(subject).to match_array(main_event_uids)
      end
    end
  end

  describe '::all_event_sessions' do
    subject { Novacast::ClientTracker::Tracker.all_event_sessions }

    before :example do
      # adds active and expired events
      add_events_to_cache main_event_uids
      add_events_to_cache sec_event_uids, true
    end

    context 'with no session' do
      it 'returns an empty list' do
        expect(subject).to be_empty
      end
    end

    context 'with active sessions' do
      before :example do
        add_sessions_to_cache main_session_uids
      end

      it 'returns all the active session uids in active events' do
        expect(subject).to match_array(main_session_uids)
      end
    end

    context 'with active and inactive sessions' do
      before :example do
        add_sessions_to_cache main_session_uids
        add_sessions_to_cache sec_session_uids, true
      end

      it 'returns only active session uids in active events' do
        expect(subject).to match_array(main_session_uids)
      end
    end
  end

  describe '::event_sessions' do
    subject { Novacast::ClientTracker::Tracker.event_sessions(event_uid) }

    before :example do
      add_events_to_cache event_uids
      add_sessions_to_cache(main_session_uids)
      add_sessions_to_cache(sec_session_uids, true)
    end

    context 'with existing event uid' do
      let(:event_uid) do
        # finds a event that has at least one session
        events_with_sess = session_event_map.values.reduce(Set.new) do |s, uid|
          s << uid
        end
        events_with_sess.to_a.sample
      end

      it 'returns all active session uids for the event' do
        event_sessions = main_session_uids.select do |uid|
          (events = session_event_map[uid]) && events.include?(event_uid)
        end
        expect(subject).to match_array(event_sessions)
      end

      it 'returns no inactive session uids for the event' do
        expect(subject & sec_session_uids).to be_empty
      end
    end

    context 'with non-existing event uid' do
      let(:event_uid) { Faker::Lorem::characters(15) }

      it 'returns an empty list' do
        expect(subject).to be_empty
      end
    end
  end

  describe '::event_users' do
    subject { Novacast::ClientTracker::Tracker.event_users(event_uid) }

    before :example do
      add_events_to_cache event_uids
      add_sessions_to_cache session_uids

      add_users_to_cache main_user_uids
      add_users_to_cache sec_user_uids, true
    end

    context 'with existing event uid' do
      let(:event_uid) do
        # finds a event that has at least one user
        sessions_with_user = user_session_map.values.reduce(Set.new) do |s, uids|
          s + uids
        end
        session_uid = sessions_with_user.to_a.sample
        session_event_map[session_uid]
      end

      it 'returns the list of users in the event' do
        users = users_for_event(event_uid, main_user_uids)
        expect(subject).to match_array(users.keys)
      end
    end

    context 'with non-existing event uid' do
      let(:event_uid) { Faker::Lorem::characters(15) }

      it 'returns an empty list' do
        expect(subject).to be_empty
      end
    end
  end

  describe '::event_user_count' do
    subject { Novacast::ClientTracker::Tracker.event_user_count(event_uid) }

    before :example do
      add_events_to_cache event_uids
      add_sessions_to_cache session_uids

      add_users_to_cache main_user_uids
      add_users_to_cache sec_user_uids, true
    end

    context 'with existing event uid' do
      let(:event_uid) do
        # finds a event that has at least one user
        sessions_with_user = user_session_map.values.reduce(Set.new) do |s, uids|
          s + uids
        end
        session_uid = sessions_with_user.to_a.sample
        session_event_map[session_uid]
      end

      it 'returns the total number of users in the event' do
        users = users_for_event event_uid, main_user_uids
        expect(subject).to eq(users.size)
      end
    end

    context 'with non-existing event uid' do
      let(:event_uid) { Faker::Lorem::characters(15) }

      it 'returns zero' do
        expect(subject).to eq(0)
      end
    end
  end

  describe '::session_users' do
    subject { Novacast::ClientTracker::Tracker.session_users(session_uid) }

    before :example do
      add_events_to_cache event_uids
      add_sessions_to_cache session_uids

      add_users_to_cache main_user_uids
      add_users_to_cache sec_user_uids, true
    end

    context 'with existing session uid' do
      let(:session_uid) do
        # finds a session that has at least one user
        sessions_with_user = user_session_map.values.reduce(Set.new) do |s, uids|
          s + uids
        end
        sessions_with_user.to_a.sample
      end

      it 'returns the list of users in the session' do
        # finds all users in this session
        users = users_for_session(session_uid, main_user_uids)
        expect(subject).to match_array(users.keys)
      end
    end

    context 'with non-existing session uid' do
      let(:session_uid) { Faker::Lorem::characters(15) }

      it 'returns an empty list' do
        expect(subject).to be_empty
      end
    end
  end

  describe '::session_user_count' do
    subject { Novacast::ClientTracker::Tracker.session_user_count(session_uid) }

    before :example do
      add_events_to_cache event_uids
      add_sessions_to_cache session_uids

      add_users_to_cache main_user_uids
      add_users_to_cache sec_user_uids, true
    end

    context 'with existing session uid' do
      let(:session_uid) do
        # finds a session that has at least one user
        sessions_with_user = user_session_map.values.reduce(Set.new) do |s, uids|
          s + uids
        end
        sessions_with_user.to_a.sample
      end

      it 'returns the total number of users in the session' do
        # finds all users in this session
        users = users_for_session(session_uid, main_user_uids)
        expect(subject).to eq(users.size)
      end
    end

    context 'with non-existing session uid' do
      let(:session_uid) { Faker::Lorem::characters(15) }

      it 'returns an empty list' do
        expect(subject).to eq(0)
      end
    end
  end

  describe '::all_user_count' do
    subject { Novacast::ClientTracker::Tracker.all_user_count }

    before :example do
      add_events_to_cache event_uids
      add_sessions_to_cache session_uids
    end

    context 'when there is only active users' do
      before :example do
        add_users_to_cache main_user_uids
      end

      it 'returns a hash' do
        expect(subject).to be_a(Hash)
      end

      it 'returns a Novacast::ClientTracker::EventUserCount object for each event' do
        result = subject
        event_uids.each do |uid|
          expect(result[uid]).to be_a(Novacast::ClientTracker::EventUserCount)
        end
      end

      it 'returns the user count for each event' do
        result = subject
        event_uids.each do |uid|
          users = users_for_event(uid, main_user_uids)
          expect(result[uid].user_count).to eq(users.size)
        end
      end

      it 'returns a Novacast::ClientTracker::UserCount object for each session within the event' do
        result = subject
        session_uids.each do |session_uid|
          event_uid = session_event_map[session_uid]
          expect(result[event_uid][session_uid]).to be_a(Novacast::ClientTracker::UserCount)
        end
      end

      it 'returns a the user count for each session within the event' do
        result = subject
        session_uids.each do |session_uid|
          event_uid = session_event_map[session_uid]
          users = users_for_session session_uid, main_user_uids
          expect(result[event_uid][session_uid].user_count).to eq(users.size)
        end
      end
    end

    context 'when there is no user' do
      it 'returns a hash' do
        expect(subject).to be_a(Hash)
      end

      it 'returns a Novacast::ClientTracker::EventUserCount object for each event' do
        result = subject
        event_uids.each do |uid|
          expect(result[uid]).to be_a(Novacast::ClientTracker::EventUserCount)
        end
      end

      it 'returns zero for each event' do
        result = subject
        event_uids.each do |uid|
          expect(result[uid].user_count).to eq(0)
        end
      end
    end
  end
end