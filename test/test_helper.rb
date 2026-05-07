# frozen_string_literal: true

require 'minitest/autorun'
require 'mocha/minitest'
require 'tmpdir'
require 'fileutils'
require 'json'

$LOAD_PATH.unshift File.expand_path('../lib', __dir__)
require 'trace_analyst'

module TraceAnalyst
  module Test
    # Minimal Redis fake for Stream / Flush / Activation::RedisTtl tests.
    class FakeRedis
      def initialize
        @kv = {}
        @streams = Hash.new { |h, k| h[k] = [] }
        @seq = 0
      end

      def call(*argv)
        cmd = argv.shift
        case cmd
        when 'EXISTS'
          @kv.key?(argv[0]) ? 1 : 0
        when 'SET'
          key = argv.shift
          val = argv.shift
          if argv[0] == 'EX'
            argv.shift
            argv.shift # ttl — not simulated for expiry
          end
          @kv[key] = val
          'OK'
        when 'DEL'
          argv.sum { |k| @kv.delete(k) ? 1 : 0 }
        when 'XADD'
          stream_key = argv.shift
          payload = argv[-1]
          @seq += 1
          id = "#{@seq}-0"
          @streams[stream_key] << [id, ['payload', payload]]
          id
        when 'XRANGE'
          stream_key = argv.shift
          argv.shift # -
          argv.shift # +
          limit = nil
          if argv[0] == 'COUNT'
            argv.shift
            limit = argv.shift.to_i
          end
          entries = @streams[stream_key].dup
          entries = entries.take(limit) if limit
          entries
        when 'XDEL'
          stream_key = argv.shift
          ids = argv.to_set
          before = @streams[stream_key]
          @streams[stream_key] = before.reject { |sid, _| ids.include?(sid) }
          before.length - @streams[stream_key].length
        when 'XLEN'
          @streams[argv[0]].length
        when 'SCAN'
          argv.shift # cursor
          raise 'MATCH missing' unless argv.shift == 'MATCH'

          pattern = argv.shift
          if argv[0] == 'COUNT'
            argv.shift
            argv.shift
          end
          prefix = pattern.delete_suffix('*')
          keys = @streams.keys.select { |k| k.start_with?(prefix) }
          ['0', keys]
        when 'KEYS'
          pattern = argv[0]
          prefix = pattern.delete_suffix('*').delete_suffix('*')
          @streams.keys.select { |k| File.fnmatch(pattern, k, File::FNM_PATHNAME) }
        else
          raise "FakeRedis unimplemented: #{cmd.inspect} #{argv.inspect}"
        end
      end
    end
  end
end

class Minitest::Test
  def setup_trace_analyst!(redis: TraceAnalyst::Test::FakeRedis.new)
    TraceAnalyst.reset_configuration!
    @tmp_storage = Dir.mktmpdir('ta-fs-')
    TraceAnalyst.configure do |c|
      c.subject_key = :shop_id
      c.redis = proc { |&blk| blk.call(redis) }
      c.storage = TraceAnalyst::Storage::LocalFsAdapter.new(root_dir: @tmp_storage)
      c.s3_prefix = 'debug'
      c.branch_prefix = 'debug'
      c.investigations_dir = 'docs/trace-investigations'
      c.local_drop_dir = 'tmp/trace-investigations'
      c.activation = TraceAnalyst::Activation::RedisTtl.new(ttl: 3600)
    end
    @redis = redis
  end

  def teardown
    super
    FileUtils.rm_rf(@tmp_storage) if @tmp_storage && File.directory?(@tmp_storage)
    TraceAnalyst.reset_configuration!
  end
end
