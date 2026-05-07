# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'optparse'
require 'pathname'
require 'set'
require 'shellwords'
require 'time'
require 'zlib'

require 'shellwords'

require_relative 'paths'
require_relative 'app_loader'
require_relative 'install_runner'

module TraceAnalyst
  module CLI
    SLUG_REGEX = /\Ainv_\d{4}_\d{2}_\d{2}_[a-z0-9_]+\z/

    class Error < StandardError; end
    class UsageError < Error; end

    class Runner
      def initialize(argv)
        @argv = argv.dup
      end

      def run
        subcommand = @argv.shift
        case subcommand
        when 'open'
          OpenCommand.new(@argv).call
        when 'index'
          IndexCommand.new(@argv).call
        when 'bundle'
          BundleCommand.new(@argv).call
        when 'timeline'
          TimelineCommand.new(@argv).call
        when 'grep'
          GrepCommand.new(@argv).call
        when 'close'
          CloseCommand.new(@argv).call
        when 'install'
          InstallRunner.new(@argv).call
        when 'flush'
          FlushCommand.new(@argv).call
        when 'enable'
          EnableCommand.new(@argv).call
        when 'disable'
          DisableCommand.new(@argv).call
        when nil, 'help', '-h', '--help'
          print_help
          exit 0
        else
          warn "Unknown subcommand: #{subcommand}"
          print_help
          exit 64
        end
      rescue UsageError => e
        warn "ERROR: #{e.message}"
        exit 64
      rescue Error => e
        warn "ERROR: #{e.message}"
        exit 1
      end

      def print_help
        puts <<~USAGE
          Usage:
            trace-analyst open <slug> --subject <id> [--topic "..."]
                   (alias: --shop <id>)
            trace-analyst index <path-to-ndjson>
            trace-analyst bundle <slug> --round <N> [--raw-dir <path>]
            trace-analyst timeline <slug> --round <N> [--where path=value] [--label L] [--limit N]
            trace-analyst grep <slug> --round <N> [--where path=value] [--label L] [--group-by path]
            trace-analyst close <slug>
            trace-analyst install [--subject-key shop_id] [--repo-root PATH] [--check]
            trace-analyst flush
            trace-analyst enable <subject_id>
            trace-analyst disable <subject_id>

          Slug shape: inv_<YYYY_MM_DD>_<topic_snake_case>

          Set TRACE_ANALYST_REPO_ROOT to anchor paths (defaults to pwd).
          For flush/enable/disable, run from a Rails app root or set TRACE_ANALYST_REPO_ROOT.
        USAGE
      end
    end

    module NdjsonFilters
      module_function

      def parse_where(flag)
        idx = flag.index('=')
        raise UsageError, "--where must be path=value, got: #{flag.inspect}" if idx.nil?

        path = safe_slice(flag, 0, idx).strip
        value = safe_slice(flag, idx + 1, flag.length).strip
        raise UsageError, '--where path cannot be empty' if path.empty?

        [path, value]
      end

      def safe_slice(str, a, b)
        str.respond_to?(:byteslice) ? str.byteslice(a...b) : str[a...b]
      end

      def dig_entry(entry, dotted_path)
        return nil if entry.nil? || dotted_path.to_s.empty?

        cur = entry
        dotted_path.split('.').each do |seg|
          return nil unless cur.is_a?(Hash)

          cur = cur[seg] || cur[seg.to_sym]
        end
        cur
      end

      def value_matches?(actual, expected_str)
        return true if actual.to_s == expected_str
        return false if expected_str.nil?

        numeric_equal?(actual, expected_str)
      end

      def numeric_equal?(actual, expected_str)
        return false unless expected_str.match?(/\A-?\d+\z/)

        exp = expected_str.to_i
        case actual
        when Integer then actual == exp
        when Float then actual.to_i == exp
        when String then actual.match?(/\A-?\d+\z/) && actual.to_i == exp
        else false
        end
      end

      def row_matches?(entry, where_pairs, label_or)
        where_pairs.each do |path, val|
          return false unless value_matches?(dig_entry(entry, path), val)
        end
        return true if label_or.empty?

        lab = entry['label']
        label_or.any? { |l| lab == l }
      end

      def each_entry(path)
        File.foreach(path, encoding: 'UTF-8') do |line|
          line = line.strip
          next if line.empty?

          yield JSON.parse(line)
        rescue JSON::ParserError
          next
        end
      end
    end

    module Slug
      module_function

      def validate!(slug)
        raise UsageError, 'slug is required' if slug.to_s.empty?
        unless slug.match?(SLUG_REGEX)
          raise UsageError,
                "slug #{slug.inspect} does not match #{SLUG_REGEX.source}; expected inv_<YYYY_MM_DD>_<topic_snake_case>"
        end

        slug
      end

      def md_path(slug)
        File.join(Paths.investigations_dir, "#{slug}.md")
      end

      def local_dir(slug)
        File.join(Paths.local_drop_dir, slug)
      end
    end

    class TimelineCommand
      TS_WIDTH = 28
      LABEL_WIDTH = 42
      RID_WIDTH = 14
      DATA_WIDTH = 120

      def initialize(argv)
        @argv = argv
        @slug = nil
        @round = nil
        @where = []
        @labels = []
        @limit = 200
      end

      def call
        @slug = Slug.validate!(@argv.shift)
        OptionParser.new do |opts|
          opts.on('--round N', Integer) { |v| @round = v }
          opts.on('--where PAIR') { |v| @where << NdjsonFilters.parse_where(v) }
          opts.on('--label L') { |v| @labels << v }
          opts.on('--limit N', Integer) { |v| @limit = v }
        end.parse!(@argv)

        raise UsageError, '--round is required' if @round.nil?
        raise UsageError, '--limit must be positive' if @limit < 1

        ndjson_path = round_ndjson_path!
        rows = []
        NdjsonFilters.each_entry(ndjson_path) do |entry|
          next unless NdjsonFilters.row_matches?(entry, @where, @labels)

          rows << entry
        end

        rows.sort_by! { |e| e['ts'].to_s }
        rows = rows.take(@limit)
        print_table(rows)
      end

      private

      def round_ndjson_path!
        base = Slug.local_dir(@slug)
        path = File.join(base, "round-#{@round}.ndjson")
        raise Error, "no such file: #{path}" unless File.file?(path)

        md_path = Slug.md_path(@slug)
        raise Error, "no investigation MD file at #{md_path}" unless File.file?(md_path)

        path
      end

      def print_table(rows)
        hdr_ts = fit('ts', TS_WIDTH)
        hdr_lb = fit('label', LABEL_WIDTH)
        hdr_rq = fit('request_id', RID_WIDTH)
        hdr_dt = fit('data', DATA_WIDTH)
        puts "#{hdr_ts}  #{hdr_lb}  #{hdr_rq}  #{hdr_dt}"
        puts '-' * (TS_WIDTH + LABEL_WIDTH + RID_WIDTH + DATA_WIDTH + 6)

        rows.each do |e|
          ts = fit((e['ts'] || '').to_s, TS_WIDTH)
          lb = fit((e['label'] || '').to_s, LABEL_WIDTH)
          rq = fit(trunc_request_id(e['request_id']), RID_WIDTH)
          dt = fit(data_one_line(e['data']), DATA_WIDTH)
          puts "#{ts}  #{lb}  #{rq}  #{dt}"
        end
      end

      def trunc_request_id(rid)
        s = rid.to_s
        return '' if s.empty?

        s.length > RID_WIDTH ? "#{s[0, RID_WIDTH - 1]}…" : s
      end

      def data_one_line(data)
        return '' if data.nil?

        raw = JSON.generate(data)
        raw.length > DATA_WIDTH ? "#{raw[0, DATA_WIDTH - 1]}…" : raw
      end

      def fit(str, width)
        s = str.to_s
        return s.ljust(width) if s.length <= width

        "#{s[0, width - 1]}…".ljust(width)
      end
    end

    class GrepCommand
      def initialize(argv)
        @argv = argv
        @slug = nil
        @round = nil
        @where = []
        @labels = []
        @group_by = nil
      end

      def call
        @slug = Slug.validate!(@argv.shift)
        OptionParser.new do |opts|
          opts.on('--round N', Integer) { |v| @round = v }
          opts.on('--where PAIR') { |v| @where << NdjsonFilters.parse_where(v) }
          opts.on('--label L') { |v| @labels << v }
          opts.on('--group-by PATH') { |v| @group_by = v }
        end.parse!(@argv)

        raise UsageError, '--round is required' if @round.nil?

        ndjson_path = round_ndjson_path!
        if @group_by
          run_grouped(ndjson_path)
        else
          run_stream(ndjson_path)
        end
      end

      private

      def round_ndjson_path!
        base = Slug.local_dir(@slug)
        path = File.join(base, "round-#{@round}.ndjson")
        raise Error, "no such file: #{path}" unless File.file?(path)

        md_path = Slug.md_path(@slug)
        raise Error, "no investigation MD file at #{md_path}" unless File.file?(md_path)

        path
      end

      def run_stream(ndjson_path)
        File.foreach(ndjson_path, encoding: 'UTF-8') do |line|
          line = line.strip
          next if line.empty?

          entry = JSON.parse(line)
          next unless NdjsonFilters.row_matches?(entry, @where, @labels)

          puts line
        rescue JSON::ParserError
          next
        end
      end

      def run_grouped(ndjson_path)
        groups = Hash.new do |h, k|
          h[k] = { count: 0, first_ts: nil, last_ts: nil, labels: Set.new }
        end

        NdjsonFilters.each_entry(ndjson_path) do |entry|
          next unless NdjsonFilters.row_matches?(entry, @where, @labels)

          key = NdjsonFilters.dig_entry(entry, @group_by)
          g = groups[key.nil? ? :__nil__ : key]
          g[:count] += 1
          ts = entry['ts'].to_s
          if g[:first_ts].nil? || (!ts.empty? && ts < g[:first_ts])
            g[:first_ts] = ts
          end
          if g[:last_ts].nil? || (!ts.empty? && ts > g[:last_ts])
            g[:last_ts] = ts
          end
          g[:labels] << entry['label'].to_s if entry['label']
        end

        rows = groups.map do |key, g|
          display_key = key == :__nil__ ? '' : key
          lbls = g[:labels].to_a.sort.join(', ')
          [g[:count], display_key, g[:first_ts] || '—', g[:last_ts] || '—', lbls]
        end
        rows.sort_by! { |r| [-r[0], r[2].to_s] }

        puts "#{'count'.rjust(6)}  #{'group'.ljust(14)}  #{fitw('first_ts', 28)}  #{fitw('last_ts', 28)}  distinct_labels"
        puts '-' * 100
        rows.each do |count, gkey, fts, lts, lbls|
          puts "#{count.to_s.rjust(6)}  #{gkey.to_s.ljust(14)}  #{fitw(fts, 28)}  #{fitw(lts, 28)}  #{lbls}"
        end
      end

      def fitw(s, width)
        str = s.to_s
        return str.ljust(width) if str.length <= width

        "#{str[0, width - 1]}…"
      end
    end

    class OpenCommand
      def initialize(argv)
        @argv = argv
        @subject_value = nil
        @topic = nil
      end

      def call
        @slug = Slug.validate!(@argv.shift)
        parse_options!

        raise UsageError, '--subject is required (or --shop alias)' if @subject_value.nil?
        raise UsageError, '--topic is required' if @topic.to_s.empty?

        ensure_template_exists!
        ensure_md_does_not_exist!

        write_md_file!
        announce_branch_command!
        announce_human_action!
      end

      private

      def parse_options!
        OptionParser.new do |opts|
          opts.on('--subject ID') { |v| @subject_value = v }
          opts.on('--shop ID') { |v| @subject_value = v }
          opts.on('--topic TOPIC') { |v| @topic = v }
        end.parse!(@argv)
      end

      def ensure_template_exists!
        return if File.file?(Paths.template_path)

        raise Error, "missing template at #{Paths.template_path}"
      end

      def ensure_md_does_not_exist!
        path = Slug.md_path(@slug)
        return unless File.exist?(path)

        raise Error, "investigation already exists at #{path}"
      end

      def write_md_file!
        template = File.read(Paths.template_path, encoding: 'UTF-8')
        sk = TraceAnalyst.configuration.subject_key.to_s
        bp = TraceAnalyst.configuration.branch_prefix.to_s
        ldir = TraceAnalyst.configuration.local_drop_dir.to_s
        filled = template
                 .gsub('{{SLUG}}', @slug)
                 .gsub('{{SUBJECT_KEY}}', sk)
                 .gsub('{{SUBJECT_VALUE}}', @subject_value.to_s)
                 .gsub('{{TOPIC}}', @topic)
                 .gsub('{{OPENED_AT}}', Time.now.utc.iso8601)
                 .gsub('{{BRANCH_PREFIX}}', bp)
                 .gsub('{{LOCAL_DROP_DIR}}', ldir)
                 .gsub('{{GEM_VERSION}}', TraceAnalyst::VERSION)

        FileUtils.mkdir_p(Paths.investigations_dir)
        File.write(Slug.md_path(@slug), filled)
        puts "wrote #{Slug.md_path(@slug)}"
      end

      def announce_branch_command!
        bp = TraceAnalyst.configuration.branch_prefix
        puts ''
        puts 'Next steps:'
        puts "  git checkout -b #{bp}/#{@slug}"
        puts "  git add #{relative(Slug.md_path(@slug))}"
        puts "  git commit -m \"Open trace investigation #{@slug}\""
      end

      def announce_human_action!
        sk = TraceAnalyst.configuration.subject_key
        puts ''
        puts 'Action required (HUMAN):'
        puts "  Enable capture for #{sk}=#{@subject_value} (e.g. `bundle exec trace-analyst enable #{Shellwords.escape(@subject_value.to_s)}` when using Redis TTL activation,"
        puts '   or via your own feature-flag / activation adapter).'
        puts "  Record the time in the MD's Hand-off log."
      end

      def relative(path)
        Pathname.new(path).relative_path_from(Pathname.new(Paths.repo_root)).to_s
      end
    end

    class IndexCommand
      def initialize(argv)
        @argv = argv
      end

      def call
        path = @argv.shift
        raise UsageError, 'path-to-ndjson is required' if path.nil?

        abs_path = File.expand_path(path)
        raise Error, "no such file: #{abs_path}" unless File.file?(abs_path)

        slug = derive_slug_from_path(abs_path)
        Slug.validate!(slug)
        round = derive_round_from_path(abs_path)

        md_path = Slug.md_path(slug)
        raise Error, "no investigation MD file at #{md_path}" unless File.file?(md_path)

        summary = summarize(abs_path)

        append_observations_block!(md_path: md_path, round: round, path: abs_path, summary: summary)
        puts "indexed #{abs_path} as Round #{round} into #{md_path}"
        puts "summary: #{summary[:total]} entries, #{summary[:labels].size} distinct labels, " \
             "#{summary[:request_ids].size} distinct request_ids, #{summary[:redactions]} redactions"
      end

      private

      def derive_slug_from_path(abs_path)
        base = "#{Paths.local_drop_dir}/"
        unless abs_path.start_with?(base)
          raise UsageError,
                "path must be under #{Paths.local_drop_dir_relative}/<slug>/, got: #{abs_path}"
        end

        rel = abs_path.delete_prefix(base)
        rel.split(File::SEPARATOR).first
      end

      def derive_round_from_path(abs_path)
        basename = File.basename(abs_path, '.ndjson')
        match = basename.match(/\Around-(\d+)\z/)
        if match.nil?
          raise UsageError,
                "ndjson filename must match 'round-N.ndjson', got: #{File.basename(abs_path)}"
        end

        Integer(match[1])
      end

      def summarize(path)
        labels = Hash.new(0)
        request_ids = Set.new
        redactions = 0
        first_ts = nil
        last_ts = nil
        total = 0

        File.foreach(path) do |line|
          line = line.strip
          next if line.empty?

          entry = JSON.parse(line)
          total += 1
          labels[entry['label']] += 1
          request_ids << entry['request_id'] if entry['request_id']
          redactions += Array(entry['redactions']).length

          ts = entry['ts']
          next if ts.nil?

          first_ts = ts if first_ts.nil? || ts < first_ts
          last_ts = ts if last_ts.nil? || ts > last_ts
        rescue JSON::ParserError
          next
        end

        {
          total: total,
          labels: labels.sort_by { |_, c| -c }.to_h,
          request_ids: request_ids,
          redactions: redactions,
          first_ts: first_ts,
          last_ts: last_ts
        }
      end

      def append_observations_block!(md_path:, round:, path:, summary:)
        block = render_block(round: round, path: path, summary: summary)
        content = File.read(md_path, encoding: 'UTF-8')

        content = if content.include?('## Observations')
                    content.sub(/## Observations\n/, "## Observations\n\n#{block}\n")
                  else
                    "#{content.rstrip}\n\n## Observations\n\n#{block}\n"
                  end

        File.write(md_path, content)
      end

      def render_block(round:, path:, summary:)
        labels_md = if summary[:labels].empty?
                      '_(no entries — file was empty or all rows malformed)_'
                    else
                      summary[:labels].map { |label, count| "- `#{label}` × #{count}" }.join("\n")
                    end

        root = Paths.repo_root
        rel_path = path.delete_prefix("#{root}/")

        <<~MD
          ### Round #{round} — indexed #{Time.now.utc.iso8601}

          - **Source**: `#{rel_path}`
          - **Window**: #{summary[:first_ts] || '—'} → #{summary[:last_ts] || '—'}
          - **Total entries**: #{summary[:total]}
          - **Distinct request_ids**: #{summary[:request_ids].size}
          - **Total redactions**: #{summary[:redactions]}
          - **Labels** (count desc):

          #{labels_md}

          _Observations:_

          <!-- Agent: under this block fill the round checklist (then any extra prose):

          - **Hypotheses tested this round** — H<N> … (confirmed / refuted / inconclusive)
          - **Anchor outcomes** — one bullet per anchor: what we learned
          - **Hypothesis status delta** — which H<N> moved, why
          - **Next round plan** — hypothesis to test + probe placement (`trace-analyst timeline` / `grep`)

          Update Hypotheses at the top of the MD as appropriate. -->
        MD
      end
    end

    class CloseCommand
      def initialize(argv)
        @argv = argv
      end

      def call
        slug = Slug.validate!(@argv.shift)
        md_path = Slug.md_path(slug)
        raise Error, "no investigation MD file at #{md_path}" unless File.file?(md_path)

        reported = reported_files_touched(md_path)
        actual = grep_call_sites(slug)

        verify_consistency!(reported: reported, actual: actual, slug: slug)

        bp = TraceAnalyst.configuration.branch_prefix
        puts "Cleanup checklist for #{slug}:"
        if actual.empty?
          puts '  (no live call sites found — instrumentation already removed?)'
        else
          actual.sort.each { |loc| puts "  #{loc}" }
        end

        puts ''
        puts 'Next steps:'
        puts "  git checkout -b #{bp}/#{slug}-cleanup"
        puts "  # Remove the lines listed above (each one carries `investigation: '#{slug}'`)"
        puts "  trace-analyst close #{slug}    # re-run after editing to verify rg returns nothing"
        puts "  git commit -am \"Cleanup trace investigation #{slug}\""
        puts "  gh pr create --title \"[Cleanup] Remove #{slug} instrumentation\" --body \"Removes TraceAnalyst instrumentation for #{slug}.\""
        puts ''
        puts 'Action required (HUMAN):'
        puts '  Once this PR merges, disable capture for the investigated subject'
        puts '  (per your activation adapter).'
      end

      private

      def reported_files_touched(md_path)
        content = File.read(md_path, encoding: 'UTF-8')
        table_section = content[/## Instrumentation rounds\n.*?(?=\n## )/m]
        return Set.new if table_section.nil?

        cells = []
        table_section.each_line do |line|
          next unless line.start_with?('|')
          next if line.match?(/\A\|[\s\-:|]+\|\s*\z/)

          columns = line.split('|').map(&:strip)
          next if columns.length < 5

          files_cell = columns[4]
          next if files_cell.to_s.empty? || files_cell == '—' || files_cell == 'Files touched'

          cells.concat(files_cell.split(',').map(&:strip).reject(&:empty?))
        end
        cells.to_set
      end

      def grep_call_sites(slug)
        pattern = "investigation: '#{slug}'"
        root = Paths.repo_root.shellescape
        output = `cd #{root} && rg --no-heading -n -F #{pattern.shellescape} 2>/dev/null`
        inv_rel = Paths.investigations_dir_relative
        output.split("\n").filter_map do |line|
          next if line.empty?

          path, lineno, = line.split(':', 3)
          next if path.start_with?("#{inv_rel}/")
          next if path.start_with?('.cursor/skills/trace-analyst/')
          next if path.start_with?('vendor/bundle/')

          "#{path}:#{lineno}"
        end.to_set
      end

      def verify_consistency!(reported:, actual:, slug:)
        missing_in_md = actual - reported
        stale_in_md = reported - actual

        return if missing_in_md.empty? && stale_in_md.empty?

        msg = +"Files touched in MD ↔ rg results disagree for #{slug}:\n"
        missing_in_md.each { |l| msg << "  + #{l} (in code, missing from MD)\n" }
        stale_in_md.each   { |l| msg << "  - #{l} (in MD, no longer in code)\n" }
        msg << "\nUpdate the MD's Files touched cells before closing."

        raise Error, msg
      end
    end

    class BundleCommand
      DEFAULT_RAW_SUBDIR = 'raw'

      def initialize(argv)
        @argv = argv
        @round = nil
        @raw_dir = nil
      end

      def call
        slug = Slug.validate!(@argv.shift)
        parse_options!
        raise UsageError, '--round is required' if @round.nil?

        md_path = Slug.md_path(slug)
        raise Error, "no investigation MD file at #{md_path}" unless File.file?(md_path)

        base_dir = Slug.local_dir(slug)
        raw_dir = File.expand_path(@raw_dir || File.join(base_dir, DEFAULT_RAW_SUBDIR))
        raise UsageError, "--raw-dir must be under #{base_dir}, got: #{raw_dir}" unless raw_dir.start_with?(base_dir)

        gz_files = Dir.glob(File.join(raw_dir, '**', '*.ndjson.gz')).sort
        plain_files = Dir.glob(File.join(raw_dir, '**', '*.ndjson')).sort
        input_paths = gz_files + plain_files
        raise Error, "no NDJSON files found under #{raw_dir}" if input_paths.empty?

        output_path = File.join(base_dir, "round-#{@round}.ndjson")
        FileUtils.mkdir_p(base_dir)

        input_count, output_count = bundle_files(input_paths: input_paths, output_path: output_path)
        deduped = input_count - output_count

        puts "bundled #{input_paths.length} files into #{output_path}"
        puts "summary: #{input_count} input lines, #{output_count} output lines, #{deduped} deduped"
      end

      private

      def parse_options!
        OptionParser.new do |opts|
          opts.on('--round N', Integer) { |v| @round = v }
          opts.on('--raw-dir PATH') { |v| @raw_dir = v }
        end.parse!(@argv)
      end

      def bundle_files(input_paths:, output_path:)
        seen_stream_ids = Set.new
        seen_raw_lines = Set.new
        output_lines = []
        input_count = 0

        input_paths.each do |file_path|
          ingest_io = proc do |io|
            io.each_line do |line|
              line = line.strip
              next if line.empty?

              input_count += 1
              parsed = parse_json_line(line)

              if parsed && parsed['stream_id']
                stream_id = parsed['stream_id'].to_s
                next if seen_stream_ids.include?(stream_id)

                seen_stream_ids << stream_id
                output_lines << line
              else
                next if seen_raw_lines.include?(line)

                seen_raw_lines << line
                output_lines << line
              end
            end
          end

          if file_path.end_with?('.gz')
            begin
              Zlib::GzipReader.open(file_path, external_encoding: Encoding::UTF_8) do |gz|
                ingest_io.call(gz)
              end
            rescue Zlib::GzipFile::Error => e
              raise Error, "failed to read gzip file #{file_path}: #{e.message}"
            end
          else
            File.open(file_path, 'r:UTF-8') do |f|
              ingest_io.call(f)
            end
          end
        end

        body = output_lines.join("\n")
        body = "#{body}\n" unless body.empty?
        File.write(output_path, body)

        [input_count, output_lines.length]
      end

      def parse_json_line(line)
        JSON.parse(line)
      rescue JSON::ParserError
        nil
      end
    end

    class FlushCommand
      def initialize(argv)
        @argv = argv
      end

      def call
        OptionParser.new.parse!(@argv)
        AppLoader.load_rails!
        TraceAnalyst::Flush.run!
        puts 'flush complete'
      end
    end

    class EnableCommand
      def initialize(argv)
        @argv = argv
      end

      def call
        OptionParser.new.parse!(@argv)
        id = @argv.shift
        raise UsageError, 'subject_id is required' if id.nil?

        AppLoader.load_rails!
        act = TraceAnalyst.configuration.activation
        act.enable!(id)
        puts "enabled capture for subject #{id.inspect}"
      rescue NotImplementedError => e
        raise Error, "#{e.message} Use your app's admin UI or rake task to enable capture."
      end
    end

    class DisableCommand
      def initialize(argv)
        @argv = argv
      end

      def call
        OptionParser.new.parse!(@argv)
        id = @argv.shift
        raise UsageError, 'subject_id is required' if id.nil?

        AppLoader.load_rails!
        act = TraceAnalyst.configuration.activation
        act.disable!(id)
        puts "disabled capture for subject #{id.inspect}"
      rescue NotImplementedError => e
        raise Error, "#{e.message} Use your app's admin UI or rake task to disable capture."
      end
    end
  end
end
