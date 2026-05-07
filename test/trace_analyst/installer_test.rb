# frozen_string_literal: true

require 'test_helper'

class TraceAnalystInstallerTest < Minitest::Test
  def setup
    root_tmp = File.expand_path('../../tmp/installer-sandbox', __dir__)
    FileUtils.mkdir_p(root_tmp)
    @sandbox = Dir.mktmpdir('ta-install-', root_tmp)
  end

  def teardown
    FileUtils.rm_rf(@sandbox) if @sandbox && File.directory?(@sandbox)
    super
  end

  def test_copies_skill_and_docs
    TraceAnalyst::Installer.new(
      repo_root: @sandbox,
      subject_key: :shop_id,
      branch_prefix: 'trace',
      force: true
    ).run

    skill = File.join(@sandbox, '.cursor', 'skills', 'trace-analyst', 'SKILL.md')
    assert File.file?(skill), skill
    body = File.read(skill, encoding: 'UTF-8')
    assert_match(/trace-analyst-skill-version:/, body)
    assert_includes body, 'shop_id'

    init = File.join(@sandbox, 'config', 'initializers', 'trace_analyst.rb')
    assert File.file?(init), init
  end

  def test_check_passes_after_install
    TraceAnalyst::Installer.new(repo_root: @sandbox, subject_key: :shop_id, force: true).run

    TraceAnalyst::Installer.new(repo_root: @sandbox, subject_key: :shop_id).check!
  end
end
