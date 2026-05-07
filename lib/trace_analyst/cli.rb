# frozen_string_literal: true

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

require_relative File.expand_path('../trace_analyst.rb', __dir__)
require_relative 'installer'
require_relative 'cli/paths'
require_relative 'cli/app_loader'
require_relative 'cli/install_runner'
require_relative 'cli/runner'

module TraceAnalyst
  module CLI
    def self.run(argv)
      Runner.new(argv).run
    end
  end
end
