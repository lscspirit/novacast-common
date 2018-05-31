require 'jwt'

module Novacast
  # Token for asserting permissions granted to a user
  #
  # @attr [String]  issuer   - token issuer
  # @attr [String]  audience - intended audience
  # @attr [String]  user_uid - uid of the user account
  # @attr [Time]    expiration - token expiration time
  class PermissionToken
    EXP_LEEWAY = 30
    ALGORITHM  = 'HS256'.freeze

    class InvalidTokenError   < StandardError; end
    class InvalidTargetError  < StandardError; end

    attr_accessor :issuer, :audience, :user_uid, :expiration
    attr_writer   :secret
    attr_reader   :permissions, :claims

    #
    # Class Methods
    #

    # Decode a PermissionToken
    #
    # @param [String] token  - PermissionToken to be decoded
    # @param [String] secret - secret key
    # @param [Hash] claims - claims that need to be verified
    # @option claims [String] :issuer   - valid issuer
    # @option claims [String] :audience - valid audience
    def self.decode(token, secret, claims = {})
      opts = {
        exp_leeway: EXP_LEEWAY,
        algorithm:  ALGORITHM
      }

      if (iss = claims[:issuer])
        opts[:iss] = iss
        opts[:verify_iss] = true
      end

      if (aud = claims[:audience])
        opts[:aud] = aud
        opts[:verify_aud] = true
      end

      if (sub = claims[:user_uid])
        opts[:sub] = sub
        opts[:verify_sub] = true
      end

      begin
        decoded = JWT.decode token, secret, true, opts
        payload = decoded[0]

        tk_opts = (exp = payload['exp']) ? { exp: Time.at(exp) } : {}

        token = self.new payload['iss'], payload['aud'], payload['sub'], tk_opts
        perms = payload['perms'] || []
        perms.each do |p|
          token.add_permissions p[0], p[1..-1]
        end

        # process remaining claims
        claims = payload.reject { |k, v| ['iss', 'aud', 'sub', 'perms'].include?(k) }
        token.add_claims claims

        token
      rescue JWT::ExpiredSignature, JWT::ImmatureSignature
        raise InvalidTokenError, 'token has expired or is not active'
      rescue JWT::InvalidIssuerError, JWT::InvalidAudError
        raise InvalidTargetError, 'invalid issuer or audience'
      rescue JWT::InvalidSubError
        raise InvalidTargetError, 'token does not belong to the user'
      rescue JWT::DecodeError => ex
        raise InvalidTokenError, ex.message
      end
    end

    #
    # Constructor
    #

    # Initialize a new PermissionToken
    #
    # @param [String] issuer   - token issuer
    # @param [String] audience - intended audience
    # @param [String] user_uid - uid of the user account
    # @param [Hash] opts - token options
    # @option opts [Integer] :ttl - number of seconds before token expires
    # @option opts [Time]    :exp - expiration time (has precedence over :ttl)
    def initialize(issuer, audience, user_uid, opts = {})
      self.issuer   = issuer
      self.audience = audience
      self.user_uid = user_uid

      self.expiration = if (exp = opts[:exp])
        exp
      elsif (ttl_sec = opts[:ttl])
        Time.now + ttl_sec
      end

      @permissions = []
      @claims = {}
    end

    #
    # Accessors
    #

    # Action granted on resource
    #
    # @return [Array<String>] list of actions
    def actions
      @actions || []
    end

    def has_permission?(resource, action)
      perm = @permissions.find { |perm| perm[:resource] == resource }
      if perm
        perm[:actions].any? { |act| act == action }
      else
        false
      end
    end

    #
    # Actions
    #

    # Encode the token
    #
    # @return [String] an encoded PermissionToken
    def encode
      raise RuntimeError, 'secret key is not set' unless @secret

      payload = @claims.merge({
        iss: issuer,
        aud: audience,
        sub: user_uid,
        perms: permissions.map do |perm|
          # encode each set of permission into an array
          # first element - resource
          # remaining elements - actions granted
          [perm[:resource]].push(*perm[:actions])
        end
      })

      payload[:exp] = expiration.to_i if expiration

      JWT.encode payload, @secret, ALGORITHM
    end

    # Add permission being granted
    #
    # @param [String] resource - resource name
    # @param [String, Array<String>] actions - list of actions
    def add_permissions(resource, actions)
      raise ArgumentError, 'invalid resource' unless resource
      raise ArgumentError, 'invalid actions'  unless actions

      acts = actions.is_a?(Array) ? actions : [actions]
      @permissions << { resource: resource, actions: acts }
    end

    # Add additional claims
    #
    # @param [Hash<Symbol, String>] claims - additional claims
    def add_claims(claims = {})
      @claims = claims.inject(@claims) { |memo, (k, v)| memo[k.to_sym] = v; memo }
    end
  end
end