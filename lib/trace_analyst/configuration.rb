# frozen_string_literal: true

module TraceAnalyst
  class ConfigurationError < StandardError; end

  class Configuration
    attr_accessor :subject_key, :redis, :storage, :activation,
                  :investigations_dir, :local_drop_dir,
                  :branch_prefix, :s3_prefix,
                  :app_logger, :on_redactions

    def initialize
      @subject_key = :shop_id
      @redis = nil
      @storage = nil
      @activation = Activation::RedisTtl.new(ttl: 86_400)
      @investigations_dir = 'docs/trace-investigations'
      @local_drop_dir = 'tmp/trace-investigations'
      @branch_prefix = 'trace'
      @s3_prefix = 'trace'
      @app_logger = nil
      @on_redactions = nil
    end

    def logger
      @app_logger || default_logger
    end

    def default_logger
      if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger
        Rails.logger
      else
        @fallback_logger ||= ::Logger.new($stdout)
      end
    end
  end
end
