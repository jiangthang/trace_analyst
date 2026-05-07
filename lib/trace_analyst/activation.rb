# frozen_string_literal: true

module TraceAnalyst
  module Activation
    class RedisTtl
      def initialize(ttl:)
        @ttl = ttl.to_i
      end

      def enabled?(subject_id)
        TraceAnalyst.with_redis { |r| r.call('EXISTS', key(subject_id)) == 1 }
      end

      def enable!(subject_id)
        TraceAnalyst.with_redis do |r|
          r.call('SET', key(subject_id), '1', 'EX', @ttl.to_s)
        end
      end

      def disable!(subject_id)
        TraceAnalyst.with_redis { |r| r.call('DEL', key(subject_id)) }
      end

      def key(subject_id)
        "trace_analyst:enabled:#{subject_id}"
      end
    end

    class Callable
      def initialize(&block)
        @block = block
      end

      def enabled?(subject_id)
        !!@block.call(subject_id)
      end

      def enable!(*)
        raise NotImplementedError, 'TraceAnalyst::Activation::Callable is read-only for enable! — use your own flagging system'
      end

      def disable!(*)
        raise NotImplementedError, 'TraceAnalyst::Activation::Callable is read-only for disable! — use your own flagging system'
      end
    end
  end
end
