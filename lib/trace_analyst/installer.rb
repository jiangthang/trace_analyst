# frozen_string_literal: true

require 'fileutils'
require 'pathname'

module TraceAnalyst
  class Installer
    class CheckFailed < StandardError; end

    attr_reader :repo_root, :subject_key, :branch_prefix, :investigations_dir, :local_drop_dir, :force

    def initialize(repo_root:, subject_key:, branch_prefix: nil, investigations_dir: nil, local_drop_dir: nil,
                   force: false)
      @repo_root = File.expand_path(repo_root)
      @subject_key = subject_key.to_sym
      @branch_prefix = branch_prefix || 'trace'
      @investigations_dir = investigations_dir || 'docs/trace-investigations'
      @local_drop_dir = local_drop_dir || 'tmp/trace-investigations'
      @force = force
    end

    def templates_root
      File.expand_path('templates', __dir__)
    end

    def subst(text)
      text
        .gsub('{{SUBJECT_KEY}}', subject_key.to_s)
        .gsub('{{BRANCH_PREFIX}}', branch_prefix.to_s)
        .gsub('{{INVESTIGATIONS_DIR}}', investigations_dir.to_s)
        .gsub('{{LOCAL_DROP_DIR}}', local_drop_dir.to_s)
        .gsub('{{GEM_VERSION}}', TraceAnalyst::VERSION)
    end

    def run
      write_template('.cursor/skills/trace-analyst/SKILL.md', 'skills/SKILL.md')
      write_template('.cursor/commands/trace-analyst.md', 'commands/trace-analyst.md')
      write_template(File.join(investigations_dir, 'TEMPLATE.md'), 'docs/TEMPLATE.md')
      write_template(File.join(investigations_dir, 'README.md'), 'docs/README.md')
      write_initializer
      append_gitignore
    end

    def check!
      skill_path = File.join(repo_root, '.cursor', 'skills', 'trace-analyst', 'SKILL.md')
      raise CheckFailed, "missing #{skill_path}" unless File.file?(skill_path)

      header = File.read(skill_path, encoding: 'UTF-8')[/<!-- trace-analyst-skill-version:\s*([\d.]+)\s*-->/, 1]
      raise CheckFailed, 'could not parse trace-analyst-skill-version header' if header.nil?

      if Gem::Version.new(header) < Gem::Version.new(TraceAnalyst::VERSION)
        raise CheckFailed,
              "installed skill version #{header} is older than gem #{TraceAnalyst::VERSION}; run trace-analyst install"
      end

      puts "skill header #{header} OK (gem #{TraceAnalyst::VERSION})"
    end

    private

    def write_template(dest_relative, src_relative)
      dest = File.join(repo_root, dest_relative)
      src = File.join(templates_root, src_relative)
      raise "missing template #{src}" unless File.file?(src)

      FileUtils.mkdir_p(File.dirname(dest))
      if File.file?(dest) && !force
        warn "skip existing #{dest} (use --force to overwrite)"
        return
      end

      File.write(dest, subst(File.read(src, encoding: 'UTF-8')))
      puts "wrote #{dest}"
    end

    def write_initializer
      dest = File.join(repo_root, 'config', 'initializers', 'trace_analyst.rb')
      src = File.join(templates_root, 'config', 'initializers', 'trace_analyst.rb.tt')
      return unless File.file?(src)

      FileUtils.mkdir_p(File.dirname(dest))
      if File.file?(dest) && !force
        warn "skip existing #{dest} (use --force to overwrite)"
        return
      end

      File.write(dest, subst(File.read(src, encoding: 'UTF-8')))
      puts "wrote #{dest}"
    end

    def append_gitignore
      gitignore = File.join(repo_root, '.gitignore')
      line = "/#{local_drop_dir.delete_suffix('/').delete_prefix('/')}/"
      return unless File.file?(gitignore)

      body = File.read(gitignore, encoding: 'UTF-8')
      return if body.include?(line)

      File.open(gitignore, 'a', encoding: 'UTF-8') do |f|
        f.puts
        f.puts '# trace_analyst local NDJSON drops'
        f.puts line
      end
      puts "appended #{line.strip.inspect} to .gitignore"
    end
  end
end
