# frozen_string_literal: true

require 'optparse'

require_relative 'paths'
require_relative '../installer'

module TraceAnalyst
  module CLI
    class InstallRunner
      def initialize(argv)
        @argv = argv
      end

      def call
        subject_key = :shop_id
        check_only = false
        force = false
        branch_prefix = 'trace'
        investigations_dir = 'docs/trace-investigations'
        local_drop_dir = 'tmp/trace-investigations'

        OptionParser.new do |o|
          o.on('--subject-key KEY', String) { |v| subject_key = v.to_sym }
          o.on('--repo-root PATH', String) { |v| ENV['TRACE_ANALYST_REPO_ROOT'] = v }
          o.on('--branch-prefix PREFIX', String) { |v| branch_prefix = v }
          o.on('--investigations-dir RELPATH', String) { |v| investigations_dir = v }
          o.on('--local-drop-dir RELPATH', String) { |v| local_drop_dir = v }
          o.on('--check') { check_only = true }
          o.on('--force') { force = true }
        end.parse!(@argv)

        repo = Paths.repo_root
        installer = TraceAnalyst::Installer.new(
          repo_root: repo,
          subject_key: subject_key,
          branch_prefix: branch_prefix,
          investigations_dir: investigations_dir,
          local_drop_dir: local_drop_dir,
          force: force
        )

        if check_only
          begin
            installer.check!
          rescue TraceAnalyst::Installer::CheckFailed => e
            warn "ERROR: #{e.message}"
            exit 1
          end
        else
          installer.run
          puts 'trace_analyst install complete'
        end
      end
    end
  end
end
