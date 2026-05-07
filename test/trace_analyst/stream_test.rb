# frozen_string_literal: true

require 'test_helper'

class TraceAnalystStreamTest < Minitest::Test
  def setup
    setup_trace_analyst!
  end

  def test_key_for_namespaced
    assert_equal 'trace_analyst:stream:9', TraceAnalyst::Stream.key_for(9)
  end

  def test_xadd_readable_via_xrange
    id = TraceAnalyst::Stream.xadd(subject_id: 7, payload: '{"a":1}')
    entries = @redis.call('XRANGE', TraceAnalyst::Stream.key_for(7), '-', '+')
    assert_equal 1, entries.length
    assert_equal id.to_s, entries.first[0].to_s
  end
end
