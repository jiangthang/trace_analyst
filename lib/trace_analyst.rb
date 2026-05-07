# frozen_string_literal: true

require_relative 'trace_analyst/version'
require_relative 'trace_analyst/configuration'
require_relative 'trace_analyst/activation'
require_relative 'trace_analyst/redactor'
require_relative 'trace_analyst/stream'
require_relative 'trace_analyst/logger'
require_relative 'trace_analyst/storage/adapter'
require_relative 'trace_analyst/storage/s3_adapter'
require_relative 'trace_analyst/storage/local_fs_adapter'
require_relative 'trace_analyst/flush'
require_relative 'trace_analyst/flush_job'
require_relative 'trace_analyst/installer'

module TraceAnalyst
  class << self
    def configure
      yield(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def reset_configuration!
      TraceAnalyst::Redactor.reset_custom_patterns!
      @configuration = Configuration.new
    end

    def with_redis(&block)
      proc = configuration.redis
      unless proc
        raise ConfigurationError,
              'TraceAnalyst redis not configured; set TraceAnalyst.configure { |c| c.redis = proc { |&blk| ... } }'
      end

      proc.call(&block)
    end

    def for(investigation:, **subject_kwargs)
      key = configuration.subject_key
      unless subject_kwargs.key?(key) && subject_kwargs.size == 1
        raise ArgumentError,
              "TraceAnalyst.for expected exactly #{key}: and investigation:; got #{subject_kwargs.keys.inspect}"
      end

      TraceAnalyst::Logger.new(
        subject_id: subject_kwargs.fetch(key),
        investigation: investigation
      )
    end
  end
end

if defined?(Rails::Railtie)
  require_relative 'trace_analyst/engine'
end