# frozen_string_literal: true

require 'fileutils'

module TraceAnalyst
  module Storage
    # Writes gzipped objects under a root directory (mirrors S3 key layout).
    class LocalFsAdapter < Adapter
      def initialize(root_dir:)
        @root_dir = root_dir
      end

      def put_gzipped_ndjson(key:, gzipped_body:)
        path = File.join(@root_dir, key)
        FileUtils.mkdir_p(File.dirname(path))
        File.binwrite(path, gzipped_body)
      end
    end
  end
end
