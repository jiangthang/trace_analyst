# frozen_string_literal: true

require 'aws-sdk-s3'

module TraceAnalyst
  module Storage
    class S3Adapter < Adapter
      attr_reader :bucket

      def initialize(bucket:, region:, credentials:)
        @bucket = bucket
        @region = region
        @client = Aws::S3::Client.new(region: region, credentials: credentials)
      end

      def put_gzipped_ndjson(key:, gzipped_body:)
        @client.put_object(
          bucket: @bucket,
          key: key,
          body: gzipped_body,
          content_type: 'application/gzip',
          content_encoding: 'gzip'
        )
      end
    end
  end
end
