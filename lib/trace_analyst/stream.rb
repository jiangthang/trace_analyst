# frozen_string_literal: true

module TraceAnalyst
  module Stream
    KEY_PREFIX = 'trace_analyst:stream'
    MAX_LEN    = 100_000
    KEY_MATCH  = "#{KEY_PREFIX}:*".freeze

    class << self
      def key_for(subject_id)
        "#{KEY_PREFIX}:#{subject_id}"
      end

      # Returns Redis stream entry id (e.g. "1714351864123-0").
      def xadd(subject_id:, payload:)
        stream_key = key_for(subject_id)
        TraceAnalyst.with_redis do |redis|
          redis.call(
            'XADD',
            stream_key,
            'MAXLEN', '~', MAX_LEN.to_s,
            '*',
            'payload', payload
          )
        end
      end

      def with_redis(&block)
        TraceAnalyst.with_redis(&block)
      end
    end
  end
end
