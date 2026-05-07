# frozen_string_literal: true

require 'minitest/autorun'

# Load core files without booting the full `trace_analyst.rb` entry (no FlushJob / ActiveJob pull).
class PortableCoreSubprocessTest < Minitest::Test
  def test_redactor_loads_in_bare_ruby
    lib = File.expand_path('../../lib', __dir__)
    script = <<~RUBY
      $LOAD_PATH.unshift('#{lib}')
      require 'trace_analyst/version'
      require 'trace_analyst/redactor'
      TraceAnalyst::Redactor.reset_custom_patterns!
      data, reds = TraceAnalyst::Redactor.redact({ sku: 'x' })
      raise 'bad redactions' unless reds.empty?
      raise 'bad data' unless data[:sku] == 'x'
    RUBY

    assert system(RbConfig.ruby, '-e', script), 'bare-ruby redactor load failed'
  end
end
