# frozen_string_literal: true

require 'test_helper'

class TraceAnalystFlushTest < Minitest::Test
  def setup
    setup_trace_analyst!
  end

  def seed!(sid, investigation, label)
    payload = JSON.generate(
      'schema_version' => 1,
      'shop_id' => sid,
      'investigation' => investigation,
      'label' => label,
      'data' => {}
    )
    TraceAnalyst::Stream.xadd(subject_id: sid, payload: payload)
  end

  def test_uploads_per_investigation_and_drains_stream
    seed!(1, 'inv_2026_05_07_a', 'one')
    seed!(1, 'inv_2026_05_07_a', 'two')
    seed!(1, 'inv_2026_05_07_b', 'three')

    TraceAnalyst::Flush.run!

    keys = Dir.glob(File.join(@tmp_storage, 'debug', '1', '**', '*.gz'))
    assert_equal 2, keys.size

    assert_equal 0, @redis.call('XLEN', TraceAnalyst::Stream.key_for(1))
  end

  def test_raises_without_storage
    TraceAnalyst.configure do |c|
      c.storage = nil
    end

    assert_raises(TraceAnalyst::ConfigurationError) do
      TraceAnalyst::Flush.run!
    end
  end
end
