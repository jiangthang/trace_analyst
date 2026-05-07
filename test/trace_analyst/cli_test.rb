# frozen_string_literal: true

require 'test_helper'
require 'open3'

class TraceAnalystCliTest < Minitest::Test
  CLI_PATH = File.expand_path('../../bin/trace-analyst', __dir__)
  LIB = File.expand_path('../../lib', __dir__)

  def setup
    @sandbox = Dir.mktmpdir('ta-cli-')
    ENV['TRACE_ANALYST_REPO_ROOT'] = @sandbox
    TraceAnalyst.reset_configuration!
    TraceAnalyst.configure do |c|
      c.subject_key = :shop_id
      c.investigations_dir = 'docs/trace-investigations'
      c.local_drop_dir = 'tmp/trace-investigations'
      c.branch_prefix = 'debug'
    end

    FileUtils.mkdir_p(File.join(@sandbox, 'docs', 'trace-investigations'))
    FileUtils.mkdir_p(File.join(@sandbox, 'tmp', 'trace-investigations'))
    tpl = File.expand_path('../../lib/trace_analyst/templates/docs/TEMPLATE.md', __dir__)
    FileUtils.cp(tpl, File.join(@sandbox, 'docs', 'trace-investigations', 'TEMPLATE.md'))
    p = File.join(@sandbox, 'docs', 'trace-investigations', 'TEMPLATE.md')
    body = File.read(p)
    body = body.gsub('{{BRANCH_PREFIX}}', 'debug')
               .gsub('{{GEM_VERSION}}', TraceAnalyst::VERSION)
               .gsub('{{LOCAL_DROP_DIR}}', 'tmp/trace-investigations')
    File.write(p, body)
  end

  def teardown
    ENV.delete('TRACE_ANALYST_REPO_ROOT')
    FileUtils.rm_rf(@sandbox) if @sandbox && File.directory?(@sandbox)
    TraceAnalyst.reset_configuration!
    super
  end

  def run_cli(*args)
    Open3.capture3({ 'GEM_HOME' => nil, 'GEM_PATH' => nil }, 'ruby', "-I#{LIB}", CLI_PATH, *args)
  end

  def test_help_displays_usage
    out, _err, st = run_cli('help')
    assert st.success?
    assert_includes out, 'trace-analyst open'
  end

  def test_open_writes_md
    slug = 'inv_2026_05_07_cli'
    out, err, st = run_cli('open', slug, '--shop', '42', '--topic', 'cli test')
    assert st.success?, err

    md = File.join(@sandbox, 'docs', 'trace-investigations', "#{slug}.md")
    assert File.file?(md), md
    body = File.read(md)
    assert_includes body, '42'
    assert_includes body, slug
    assert_includes out, 'git checkout'
  end

  def test_index_appends_observations
    slug = 'inv_2026_05_07_ndjson'
    run_cli('open', slug, '--shop', '1', '--topic', 't')
    drop = File.join(@sandbox, 'tmp', 'trace-investigations', slug)
    FileUtils.mkdir_p(drop)
    nd = File.join(drop, 'round-1.ndjson')
    File.write(nd, "{\"label\":\"x\",\"ts\":\"2026-05-07T00:00:00.000Z\",\"data\":{}}\n")

    _out, err, st = run_cli('index', nd)
    assert st.success?, err

    md = File.join(@sandbox, 'docs', 'trace-investigations', "#{slug}.md")
    body = File.read(md)
    assert_includes body, '### Round 1'
  end
end
