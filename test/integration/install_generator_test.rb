# frozen_string_literal: true

require 'test_helper'
require 'rails/generators'
require_relative '../../lib/generators/trace_analyst/install/install_generator'

class TraceAnalystInstallGeneratorTest < Minitest::Test
  def test_generator_loads_and_installer_hooks_exist
    gen = TraceAnalyst::Generators::Install::InstallGenerator
    assert gen < Rails::Generators::Base
    assert gen.instance_methods(false).include?(:run_installer)
  end
end
