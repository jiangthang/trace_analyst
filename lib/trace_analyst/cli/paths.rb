# frozen_string_literal: true

module TraceAnalyst
  module CLI
    module Paths
      module_function

      def repo_root
        ENV.fetch('TRACE_ANALYST_REPO_ROOT', Dir.pwd)
      end

      def investigations_dir
        File.join(repo_root, TraceAnalyst.configuration.investigations_dir)
      end

      def template_path
        File.join(investigations_dir, 'TEMPLATE.md')
      end

      def local_drop_dir
        File.join(repo_root, TraceAnalyst.configuration.local_drop_dir)
      end

      def investigations_dir_relative
        TraceAnalyst.configuration.investigations_dir
      end

      def local_drop_dir_relative
        TraceAnalyst.configuration.local_drop_dir
      end

      def skill_relative_path
        '.cursor/skills/trace-analyst/SKILL.md'
      end
    end
  end
end
