# frozen_string_literal: true

module TraceAnalyst
  module Storage
    class Adapter
      def put_gzipped_ndjson(key:, gzipped_body:)
        raise NotImplementedError
      end
    end
  end
end
