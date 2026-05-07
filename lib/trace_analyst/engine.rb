# frozen_string_literal: true

require 'rails/engine'

module TraceAnalyst
  class Engine < ::Rails::Engine
    generators do
      require_relative '../../generators/trace_analyst/install/install_generator'
    end
  end
end
