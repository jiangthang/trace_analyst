# frozen_string_literal: true

require 'test_helper'

class TraceAnalystRedactorTest < Minitest::Test
  def teardown
    TraceAnalyst::Redactor.reset_custom_patterns!
    super
  end

  def test_redacts_matching_keys
    redacted, redactions = TraceAnalyst::Redactor.redact({ sku: 'X', email: 'a@b.com' })
    assert_equal '[REDACTED:email]', redacted[:email]
    assert_equal ['email'], redactions
  end

  def test_register_pattern
    TraceAnalyst::Redactor.register_pattern(/account_id/i, label: 'carrier_account')
    redacted, redactions = TraceAnalyst::Redactor.redact({ account_id: 'AC-1' })
    assert_equal '[REDACTED:carrier_account]', redacted[:account_id]
    assert_equal ['account_id'], redactions
  end

  def test_type_error_on_bad_value
    assert_raises(TraceAnalyst::TypeError) do
      TraceAnalyst::Redactor.redact({ bad: Object.new })
    end
  end
end
