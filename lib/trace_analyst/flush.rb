# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'stringio'
require 'zlib'

module TraceAnalyst
  # Drains trace_analyst:stream:* Redis streams into gzipped NDJSON via configured storage.
  class Flush
    BATCH_SIZE = 1_000

    class << self
      def run!(store: nil)
        store ||= TraceAnalyst.configuration.storage
        raise TraceAnalyst::ConfigurationError, 'TraceAnalyst storage not configured' unless store

        Stream.with_redis do |redis|
          each_stream_key(redis) do |stream_key|
            subject_id = parse_subject_id(stream_key)
            next if subject_id.nil?

            entries = read_batch(redis, stream_key)
            next if entries.empty?

            uploaded_ids = upload_grouped(store: store, subject_id: subject_id, entries: entries)
            redis.call('XDEL', stream_key, *uploaded_ids) if uploaded_ids.any?
          end
        end
      end

      private

      def each_stream_key(redis)
        cursor = '0'
        loop do
          cursor, keys = redis.call('SCAN', cursor, 'MATCH', TraceAnalyst::Stream::KEY_MATCH, 'COUNT', '100')
          Array(keys).each { |k| yield k }
          break if cursor.to_s == '0'
        end
      end

      def read_batch(redis, stream_key)
        raw = redis.call('XRANGE', stream_key, '-', '+', 'COUNT', BATCH_SIZE.to_s)
        Array(raw).filter_map do |entry|
          stream_id, fields = entry
          payload_json = extract_payload_field(fields)
          next if payload_json.nil?

          parsed = safe_parse(payload_json, stream_key: stream_key, stream_id: stream_id)
          next if parsed.nil?

          parsed['stream_id'] = stream_id
          [stream_id, parsed]
        end
      end

      def extract_payload_field(fields)
        return nil if fields.nil?

        flat = Array(fields)
        flat.each_with_index do |val, i|
          return flat[i + 1] if val == 'payload'
        end
        nil
      end

      def safe_parse(json, stream_key:, stream_id:)
        JSON.parse(json)
      rescue JSON::ParserError => e
        TraceAnalyst.configuration.logger.warn(
          "TraceAnalyst::Flush skipping malformed entry on #{stream_key}/#{stream_id}: #{e.message}"
        )
        nil
      end

      def upload_grouped(store:, subject_id:, entries:)
        uploaded_ids = []
        prefix = TraceAnalyst.configuration.s3_prefix

        entries.group_by { |_id, payload| payload['investigation'] }.each do |investigation, group|
          if investigation.nil? || investigation.to_s.strip.empty?
            TraceAnalyst.configuration.logger.warn(
              'TraceAnalyst::Flush dropping ' \
              "#{group.length} entries with missing investigation slug for subject_id=#{subject_id}"
            )
            uploaded_ids.concat(group.map(&:first))
            next
          end

          ndjson = "#{group.map { |_id, payload| JSON.generate(payload) }.join("\n")}\n"
          gzipped = gzip(ndjson)
          key = build_key(prefix: prefix, subject_id: subject_id, investigation: investigation)

          store.put_gzipped_ndjson(key: key, gzipped_body: gzipped)
          uploaded_ids.concat(group.map(&:first))
        rescue StandardError => e
          TraceAnalyst.configuration.logger.error(
            'TraceAnalyst::Flush upload failed for ' \
            "subject_id=#{subject_id} investigation=#{investigation}: #{e.message}"
          )
        end

        uploaded_ids
      end

      def build_key(prefix:, subject_id:, investigation:)
        now = Time.now.utc
        date = now.strftime('%Y-%m-%d')
        hh_mm = now.strftime('%H-%M')
        "#{prefix}/#{subject_id}/#{investigation}/#{date}/#{hh_mm}-#{SecureRandom.uuid}.ndjson.gz"
      end

      def gzip(body)
        io = StringIO.new
        io.set_encoding(Encoding::ASCII_8BIT)
        gz = Zlib::GzipWriter.new(io)
        gz.write(body)
        gz.close
        io.string
      end

      def parse_subject_id(stream_key)
        prefix = "#{TraceAnalyst::Stream::KEY_PREFIX}:"
        return nil unless stream_key.start_with?(prefix)

        stream_key.delete_prefix(prefix)
      end
    end
  end
end
