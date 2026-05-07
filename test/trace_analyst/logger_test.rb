# frozen_string_literal: true

require 'test_helper'

class TraceAnalystLoggerTest < Minitest::Test
  def setup
    setup_trace_analyst!
    @redis.call('SET', "trace_analyst:enabled:#{shop_id}", '1', 'EX', '3600')
  end

  def shop_id
    42
  end

  def test_no_op_when_activation_off
    TraceAnalyst.reset_configuration!
    setup_trace_analyst!
    assert_nil TraceAnalyst.for(shop_id: shop_id, investigation: 'inv_2026_05_07_x').log(label: 'x')
  end

  def test_writes_payload_with_schema_version_and_subject_key
    TraceAnalyst.for(shop_id: shop_id, investigation: 'inv_2026_05_07_x')
                .log(label: 'rate_calc.input', data: { sku: 'AB-12', qty: 3 })

    key = TraceAnalyst::Stream.key_for(shop_id)
    entries = @redis.call('XRANGE', key, '-', '+')
    assert_equal 1, entries.length

    payload = JSON.parse(entries.first[1][1])
    assert_equal 1, payload['schema_version']
    assert_equal shop_id, payload['shop_id']
    assert_equal 'inv_2026_05_07_x', payload['investigation']
    assert_equal 'rate_calc.input', payload['label']
    assert_equal({ 'sku' => 'AB-12', 'qty' => 3 }, payload['data'])
    assert_equal [], payload['redactions']
  end

  def test_callable_activation
    TraceAnalyst.configure do |c|
      c.activation = TraceAnalyst::Activation::Callable.new { |sid| sid == shop_id }
    end

    TraceAnalyst.for(shop_id: shop_id, investigation: 'inv_a').log(label: 'one')
    TraceAnalyst.for(shop_id: 99, investigation: 'inv_a').log(label: 'two')

    assert_equal 1, @redis.call('XLEN', TraceAnalyst::Stream.key_for(shop_id))
    assert_equal 0, @redis.call('XLEN', TraceAnalyst::Stream.key_for(99))
  end

  def test_wrong_kwargs_raises
    assert_raises(ArgumentError) { TraceAnalyst.for(investigation: 'x') }
    assert_raises(ArgumentError) { TraceAnalyst.for(shop_id: 1, other: 2, investigation: 'x') }
  end
end
