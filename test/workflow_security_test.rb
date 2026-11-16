# Run all offline workflow checks: ruby test/workflow_security_test.rb
require 'minitest/autorun'
require 'shellwords'
require 'yaml'

class WorkflowSecurityTest < Minitest::Test
  WORKFLOWS = File.expand_path('../.github/workflows', __dir__)

  def setup
    @review_source = File.read(File.join(WORKFLOWS, 'claude-pr-review.yml'))
    @review = YAML.safe_load(@review_source).fetch('jobs').fetch('review')
    @inputs = @review.fetch('steps').find do |step|
      step.fetch('uses', '').start_with?('anthropics/claude-code-action@')
    end.fetch('with')
  end

  def test_pro_01_review_does_not_enable_tag_mode
    assert_equal false, @inputs.fetch('track_progress', false),
                 'Progress tracking injects edit permissions and commit/push tools'
    refute_empty @inputs.fetch('prompt'), 'An explicit prompt selects agent mode'
  end

  def test_pro_01_review_uses_scoped_workflow_token
    assert_equal '${{ github.token }}', @inputs['github_token'],
                 'Without an explicit workflow token the Action requests an App token'
    assert_equal({ 'contents' => 'read', 'pull-requests' => 'write' },
                 @review.fetch('permissions'))
    checkout = @review.fetch('steps').find do |step|
      step.fetch('uses', '').start_with?('actions/checkout@')
    end
    assert_equal false, checkout.fetch('with')['persist-credentials']
  end

  def test_pro_01_review_denies_mutation_tools
    args = Shellwords.split(@inputs.fetch('claude_args'))
    deny_index = args.index('--disallowedTools')
    refute_nil deny_index, 'An allow-list alone does not deny mutation tools'
    denied = args.fetch(deny_index + 1).split(',')
    %w[Edit MultiEdit Write NotebookEdit Bash(git:*)
       mcp__github_file_ops__commit_files mcp__github_file_ops__delete_files].each do |tool|
      assert_includes denied, tool
    end
    mode_index = args.index('--permission-mode')
    refute_nil mode_index
    assert_equal 'default', args.fetch(mode_index + 1)
  end

  def test_pro_02_reviewer_is_disabled_before_unverified_bootstrap
    assert_equal '${{ false }}', @review['if'],
                 'Keep the entire credentialed job disabled until its CLI bootstrap is hash-verified'
  end

  def test_pro_n1_no_unconditional_cannot_push_claim
    refute_match(/contents:\s*read[^\n]*CANNOT push/i, @review_source,
                 'Workflow permissions alone do not bound an independently issued App token')
  end
end
