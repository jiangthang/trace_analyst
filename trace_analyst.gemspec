# frozen_string_literal: true

require_relative 'lib/trace_analyst/version'

Gem::Specification.new do |spec|
  spec.name          = 'trace_analyst'
  spec.version       = TraceAnalyst::VERSION
  spec.authors       = ['PackGenie']
  spec.summary       = 'Structured production debug capture: Redis streams, S3 NDJSON batching, and Cursor-driven investigation CLI.'
  spec.license       = 'MIT'

  spec.required_ruby_version = '>= 3.1'

  spec.files = Dir.chdir(__dir__) do
    Dir['lib/**/*'].reject { |p| File.directory?(p) } +
      %w[LICENSE README.md trace_analyst.gemspec bin/trace-analyst]
  end

  spec.bindir        = 'bin'
  spec.executables   = ['trace-analyst']
  spec.require_paths = ['lib']

  spec.add_dependency 'activejob', '>= 6.1'
  spec.add_dependency 'railties', '>= 6.1'
  spec.add_dependency 'aws-sdk-s3', '~> 1'

  spec.add_development_dependency 'minitest', '~> 5'
  spec.add_development_dependency 'mocha', '~> 2'
  spec.add_development_dependency 'railties', '>= 7.0'
  spec.add_development_dependency 'rake', '~> 13'
  spec.add_development_dependency 'redis', '~> 5'
end
