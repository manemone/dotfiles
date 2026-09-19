# frozen_string_literal: true

require "minitest/autorun"
require "fileutils"
require "open3"
require "tmpdir"
require "stringio"

require_relative "../lib/doc_id/tool"

module DocIdTestHelper
  def silence_stdout
    orig = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = orig
  end

  def capture_stdout
    orig = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = orig
  end

  def git_env
    { "GIT_DIR" => nil, "GIT_WORK_TREE" => nil, "GIT_INDEX_FILE" => nil }
  end
end

class DocIdCheckTest < Minitest::Test
  include DocIdTestHelper

  def setup
    @repo_root = Dir.mktmpdir "doc-id-check-test"
    @docs_dir = File.join @repo_root, "docs"
    FileUtils.mkdir_p File.join(@docs_dir, "design")
    @tool = DocId::Tool.new repo_root: @repo_root
  end

  def teardown
    FileUtils.rm_rf @repo_root
  end

  def test_returns_zero_when_all_files_have_doc_prefix
    File.write File.join(@docs_dir, "design", "DOC-2606281807_test.md"), "# test"
    silence_stdout { assert_equal 0, @tool.check }
  end

  def test_returns_one_when_file_lacks_doc_prefix
    File.write File.join(@docs_dir, "design", "no_prefix.md"), "# test"
    silence_stdout { assert_equal 1, @tool.check }
  end

  def test_returns_one_when_file_has_unassigned_placeholder
    File.write File.join(@docs_dir, "design", "DOC-DOCID_PLACEHOLDER_計画.md"), "# test"
    silence_stdout { assert_equal 1, @tool.check }
  end

  def test_skips_readme_files
    File.write File.join(@docs_dir, "design", "README.md"), "# index"
    silence_stdout { assert_equal 0, @tool.check }
  end
end

class DocIdVerifyTest < Minitest::Test
  include DocIdTestHelper

  NONEXISTENT_ID = "DOC-9999999999"
  TEST_FILE = "DOC-2606281807_test.md"

  def setup
    @repo_root = Dir.mktmpdir "doc-id-verify-test"
    @docs_dir = File.join @repo_root, "docs"
    FileUtils.mkdir_p File.join(@docs_dir, "design")
    @tool = DocId::Tool.new repo_root: @repo_root
  end

  def teardown
    FileUtils.rm_rf @repo_root
  end

  def test_returns_zero_when_all_references_are_valid
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"), "[link](docs/design/#{TEST_FILE})"
    silence_stdout { assert_equal 0, @tool.verify }
  end

  def test_returns_one_when_a_doc_id_does_not_exist
    File.write File.join(@repo_root, "README.md"), "See #{NONEXISTENT_ID} for details."
    silence_stdout { assert_equal 1, @tool.verify }
  end

  def test_detects_broken_markdown_link_paths
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    FileUtils.mkdir_p File.join(@docs_dir, "archive")
    File.write File.join(@repo_root, "README.md"), "[link](docs/archive/#{TEST_FILE})"
    silence_stdout { assert_equal 1, @tool.verify }
  end

  def test_skips_code_fences
    File.write File.join(@repo_root, "README.md"), "```\nSee #{NONEXISTENT_ID} in code.\n```\n"
    silence_stdout { assert_equal 0, @tool.verify }
  end

  def test_detects_references_spanning_multiple_lines
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"),
               "See #{NONEXISTENT_ID}\nand also [link](docs/design/#{TEST_FILE})\nfor details."
    silence_stdout { assert_equal 1, @tool.verify }
  end

  def test_skips_same_indent_nested_fences_with_info_strings
    File.write File.join(@repo_root, "README.md"),
               "```\nSee #{NONEXISTENT_ID}\n```yaml\n  key: #{NONEXISTENT_ID}\n```\n```\n"
    silence_stdout { assert_equal 0, @tool.verify }
  end

  def test_does_not_match_markdown_links_spanning_newlines
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"), "[link](docs/design/\n#{TEST_FILE})"
    silence_stdout { assert_equal 0, @tool.verify }
  end

  def test_detects_broken_bare_ref_with_filename_suffix
    File.write File.join(@repo_root, "README.md"),
               "地の文で #{NONEXISTENT_ID}_存在しない文書.md に触れる。"
    silence_stdout { assert_equal 1, @tool.verify }
  end

  def test_does_not_double_report_broken_markdown_link_with_filename_suffix
    File.write File.join(@repo_root, "README.md"),
               "[link](docs/design/#{NONEXISTENT_ID}_存在しない文書.md)"
    output = capture_stdout { @tool.verify }
    assert_equal 1, output.lines.count { |l| l.start_with? "❌" }
  end

  # docs/spec/ は仕様書ディレクトリであり、テストコードの spec/ とは違う。
  # 除外対象にすると、iosci のように壊れ参照を verify が見逃す（実バグの regression）。
  def test_detects_broken_refs_inside_docs_spec_directory
    FileUtils.mkdir_p File.join(@docs_dir, "spec")
    File.write File.join(@docs_dir, "spec", "tech.md"), "See #{NONEXISTENT_ID} for details."
    silence_stdout { assert_equal 1, @tool.verify }
  end

  # docs/ の外にある test/ tests/ spec/ は従来どおり除外され続ける。
  def test_still_excludes_test_directories_outside_docs
    FileUtils.mkdir_p File.join(@repo_root, "spec")
    File.write File.join(@repo_root, "spec", "fixture.md"), "See #{NONEXISTENT_ID} for details."
    silence_stdout { assert_equal 0, @tool.verify }
  end
end

class DocIdVerifyGitTest < Minitest::Test
  include DocIdTestHelper

  NONEXISTENT_ID = "DOC-9999999999"
  TEST_FILE = "DOC-2606281807_test.md"

  def setup
    @repo_root = Dir.mktmpdir "doc-id-verify-git-test"
    @docs_dir = File.join @repo_root, "docs"
    Open3.capture2 git_env, "git", "init", chdir: @repo_root
    Open3.capture2 git_env, "git", "config", "user.email", "test@example.com", chdir: @repo_root
    Open3.capture2 git_env, "git", "config", "user.name", "Test", chdir: @repo_root
    FileUtils.mkdir_p File.join(@docs_dir, "設計")
    File.write File.join(@docs_dir, "設計", TEST_FILE), "# 設計書"
    Open3.capture2 git_env, "git", "add", ".", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "init", chdir: @repo_root
    @tool = DocId::Tool.new repo_root: @repo_root
  end

  def teardown
    FileUtils.rm_rf @repo_root
  end

  def test_scans_files_with_non_ascii_paths_via_git_ls_files
    File.write File.join(@repo_root, "README.md"), "[link](docs/設計/#{TEST_FILE})"
    Open3.capture2 git_env, "git", "add", "README.md", chdir: @repo_root
    silence_stdout { assert_equal 0, @tool.verify }
  end

  def test_detects_broken_refs_in_non_ascii_paths
    File.write File.join(@repo_root, "README.md"), "See #{NONEXISTENT_ID}"
    Open3.capture2 git_env, "git", "add", "README.md", chdir: @repo_root
    silence_stdout { assert_equal 1, @tool.verify }
  end

  def test_skips_files_missing_from_working_tree
    tracked = File.join @docs_dir, "設計", TEST_FILE
    FileUtils.rm tracked
    File.write File.join(@repo_root, "README.md"), "[link](docs/設計/#{TEST_FILE})"
    Open3.capture2 git_env, "git", "add", "README.md", chdir: @repo_root
    silence_stdout { @tool.verify }
  end

  def test_detects_broken_refs_in_extensionless_shebang_script
    script = File.join @repo_root, "bin", "tool"
    FileUtils.mkdir_p File.dirname(script)
    File.write script, "#!/bin/sh\n# See #{NONEXISTENT_ID}\n"
    Open3.capture2 git_env, "git", "add", "bin/tool", chdir: @repo_root
    silence_stdout { assert_equal 1, @tool.verify }
  end

  def test_skips_extensionless_files_without_shebang
    non_script = File.join @repo_root, "bin", "data"
    FileUtils.mkdir_p File.dirname(non_script)
    File.write non_script, "See #{NONEXISTENT_ID}\n"
    Open3.capture2 git_env, "git", "add", "bin/data", chdir: @repo_root
    silence_stdout { assert_equal 0, @tool.verify }
  end
end

class DocIdVerifyRepoRootPathTest < Minitest::Test
  include DocIdTestHelper

  # excluded_path? はディレクトリ成分単位で判定する必要がある。リポジトリ自体が
  # test/ の下に置かれているだけで参照検証が丸ごと無効化されてはならない。
  def test_verify_still_detects_broken_refs_when_repo_root_contains_excluded_segment
    parent = Dir.mktmpdir "doc-id-verify-parent"
    repo_root = File.join parent, "test", "myrepo"
    FileUtils.mkdir_p repo_root
    Open3.capture2 git_env, "git", "init", chdir: repo_root
    Open3.capture2 git_env, "git", "config", "user.email", "test@example.com", chdir: repo_root
    Open3.capture2 git_env, "git", "config", "user.name", "Test", chdir: repo_root
    File.write File.join(repo_root, "README.md"), "See DOC-9999999999 for details.\n"
    Open3.capture2 git_env, "git", "add", ".", chdir: repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "init", chdir: repo_root

    tool = DocId::Tool.new repo_root: repo_root
    silence_stdout { assert_equal 1, tool.verify }
  ensure
    FileUtils.rm_rf parent
  end
end

class DocIdAssignTest < Minitest::Test
  include DocIdTestHelper

  def setup
    @old_git_env = ENV.slice "GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"
    ENV.delete "GIT_DIR"
    ENV.delete "GIT_WORK_TREE"
    ENV.delete "GIT_INDEX_FILE"

    @repo_root = Dir.mktmpdir "doc-id-assign-test"
    @docs_dir = File.join @repo_root, "docs"
    Open3.capture2 git_env, "git", "init", chdir: @repo_root
    Open3.capture2 git_env, "git", "config", "user.email", "test@example.com", chdir: @repo_root
    Open3.capture2 git_env, "git", "config", "user.name", "Test", chdir: @repo_root
    FileUtils.mkdir_p File.join(@docs_dir, "design")
    @tool = DocId::Tool.new repo_root: @repo_root
  end

  def teardown
    FileUtils.rm_rf @repo_root
    @old_git_env.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end

  def commit_file(path, content)
    File.write File.join(@repo_root, path), content
    Open3.capture2 git_env, "git", "add", path, chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add #{path}", chdir: @repo_root
  end

  def test_assigns_doc_id_to_a_file_without_one
    path = File.join @docs_dir, "design", "no_prefix.md"
    File.write path, "# Test\n"
    Open3.capture2 git_env, "git", "add", "docs/design/no_prefix.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add", chdir: @repo_root
    silence_stdout { assert_equal 0, @tool.assign("docs/design/no_prefix.md") }
    renamed = Dir.glob File.join(@docs_dir, "design", "DOC-*_no_prefix.md")
    assert_equal 1, renamed.size
  end

  def test_skips_file_with_proper_doc_id
    test_file = "DOC-2606281807_test.md"
    path = File.join @docs_dir, "design", test_file
    commit_file "docs/design/#{test_file}", "# Test\n"
    silence_stdout { assert_equal 0, @tool.assign("docs/design/#{test_file}") }
    assert File.exist?(path)
  end

  def test_does_not_treat_midnight_timestamp_as_placeholder
    legit_file = "docs/design/DOC-2607190000_設計.md"
    path = File.join @repo_root, legit_file
    File.write path, "# 設計\n"
    Open3.capture2 git_env, "git", "add", legit_file, chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add legit midnight file", chdir: @repo_root
    silence_stdout { assert_equal 0, @tool.assign(legit_file) }
    assert File.exist?(path)
  end

  def test_placeholder_file_renamed_and_content_replaced
    path = File.join @repo_root, "docs/design/DOC-DOCID_PLACEHOLDER_計画.md"
    File.write path, "# 計画\n> **DOC-ID**: DOC-DOCID_PLACEHOLDER_計画\n"
    Open3.capture2 git_env, "git", "add", "docs/design/DOC-DOCID_PLACEHOLDER_計画.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add placeholder", chdir: @repo_root

    silence_stdout { @tool.assign "docs/design/DOC-DOCID_PLACEHOLDER_計画.md" }

    renamed = Dir.glob File.join(@docs_dir, "design", "DOC-*_計画.md")
    assert_equal 1, renamed.size
    refute_includes File.basename(renamed.first), "DOCID_PLACEHOLDER"

    content = File.read renamed.first
    refute_includes content, "DOC-DOCID_PLACEHOLDER"
    assert_match(/DOC-\d{6}\d{4}/, content)
  end

  def test_updates_references_across_multiple_file_types_and_locations
    # .md at repo root
    readme = File.join @repo_root, "README.md"
    File.write readme, "[計画](docs/design/DOC-DOCID_PLACEHOLDER_計画.md) と DOC-DOCID_PLACEHOLDER\n"
    Open3.capture2 git_env, "git", "add", "README.md", chdir: @repo_root
    # .sh in a subdirectory
    shared_dir = File.join @repo_root, "shared"
    FileUtils.mkdir_p shared_dir
    sh_file = File.join shared_dir, "helpers.sh"
    File.write sh_file, "# 設計は DOC-DOCID_PLACEHOLDER_計画 を参照\n"
    Open3.capture2 git_env, "git", "add", "shared/helpers.sh", chdir: @repo_root
    # .yml in a subdirectory
    examples = File.join @repo_root, "examples"
    FileUtils.mkdir_p examples
    yml_file = File.join examples, "conf.yml"
    File.write yml_file, "doc: DOC-DOCID_PLACEHOLDER_計画\n"
    Open3.capture2 git_env, "git", "add", "examples/conf.yml", chdir: @repo_root
    # .md in a subdirectory
    md_file = File.join examples, "README.md"
    File.write md_file, "see DOC-DOCID_PLACEHOLDER_計画\n"
    Open3.capture2 git_env, "git", "add", "examples/README.md", chdir: @repo_root
    # Placeholder file itself
    path = File.join @repo_root, "docs/design/DOC-DOCID_PLACEHOLDER_計画.md"
    File.write path, "# 計画\n> **DOC-ID**: DOC-DOCID_PLACEHOLDER_計画\n"
    Open3.capture2 git_env, "git", "add", "docs/design/DOC-DOCID_PLACEHOLDER_計画.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add files", chdir: @repo_root

    silence_stdout { @tool.assign "docs/design/DOC-DOCID_PLACEHOLDER_計画.md" }

    readme_content = File.read readme
    assert_match(%r{\[計画\]\(docs/design/DOC-\d{10}_計画\.md\) と DOC-DOCID_PLACEHOLDER}, readme_content)

    sh_content = File.read sh_file
    assert_match(/# 設計は DOC-\d{10}_計画 を参照/, sh_content)

    yml_content = File.read yml_file
    assert_match(/doc: DOC-\d{10}_計画/, yml_content)

    md_content = File.read md_file
    assert_match(/see DOC-\d{10}_計画/, md_content)
  end

  def test_preserves_suffix_bearing_doc_ids_and_replaces_only_document_reference
    readme = File.join @repo_root, "README.md"
    File.write readme, "DOC-DOCID_PLACEHOLDER_計画 と DOC-DOCID_PLACEHOLDER と DOC-DOCID_PLACEHOLDER-a の比較\n"
    Open3.capture2 git_env, "git", "add", "README.md", chdir: @repo_root
    path = File.join @repo_root, "docs/design/DOC-DOCID_PLACEHOLDER_計画.md"
    File.write path, "# 計画\n"
    Open3.capture2 git_env, "git", "add", "docs/design/DOC-DOCID_PLACEHOLDER_計画.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add files", chdir: @repo_root

    silence_stdout { @tool.assign "docs/design/DOC-DOCID_PLACEHOLDER_計画.md" }

    content = File.read readme
    assert_includes content, "DOC-DOCID_PLACEHOLDER-a"
    assert_match(/DOC-\d{10}_計画/, content)
    assert_includes content, "DOC-DOCID_PLACEHOLDER と"
  end

  def test_assigning_one_placeholder_does_not_corrupt_link_to_another_placeholder_document
    design_dir = File.join @docs_dir, "design"
    tracking_dir = File.join @docs_dir, "tracking"
    FileUtils.mkdir_p tracking_dir
    doc_a = File.join design_dir, "DOC-DOCID_PLACEHOLDER_店舗情報.md"
    doc_b = File.join tracking_dir, "DOC-DOCID_PLACEHOLDER_未確定事項.md"
    File.write doc_a, "# 店舗情報\n[未確定事項](../tracking/DOC-DOCID_PLACEHOLDER_未確定事項.md)\n"
    File.write doc_b, "# 未確定事項\n[店舗情報](../design/DOC-DOCID_PLACEHOLDER_店舗情報.md)\n"
    Open3.capture2 git_env, "git", "add", "docs/design/DOC-DOCID_PLACEHOLDER_店舗情報.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "add", "docs/tracking/DOC-DOCID_PLACEHOLDER_未確定事項.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add A and B", chdir: @repo_root

    silence_stdout { @tool.assign "docs/design/DOC-DOCID_PLACEHOLDER_店舗情報.md" }

    renamed_a = Dir.glob(File.join(design_dir, "DOC-*_店舗情報.md")).first
    refute_nil renamed_a
    content_a = File.read renamed_a
    # 穴1: Bはまだ未採番なので、Bへのプレースホルダ参照は書き換わらず残る
    assert_includes content_a, "DOC-DOCID_PLACEHOLDER_未確定事項.md"

    content_b = File.read doc_b
    refute_includes content_b, "DOC-DOCID_PLACEHOLDER_店舗情報"
    assert_match(%r{\.\./design/DOC-\d{10}_店舗情報\.md}, content_b)

    Open3.capture2 git_env, "git", "add", "-A", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "assign a", chdir: @repo_root

    silence_stdout { @tool.assign "docs/tracking/DOC-DOCID_PLACEHOLDER_未確定事項.md" }

    renamed_b = Dir.glob(File.join(tracking_dir, "DOC-*_未確定事項.md")).first
    refute_nil renamed_b
    content_a_after = File.read renamed_a
    refute_includes content_a_after, "DOC-DOCID_PLACEHOLDER"
    assert_match(%r{\.\./tracking/DOC-\d{10}(?:-[a-z])?_未確定事項\.md}, content_a_after)
  end

  def test_assign_does_not_corrupt_placeholder_link_to_document_whose_name_shares_a_prefix
    readme = File.join @repo_root, "README.md"
    File.write readme, "[計画書](docs/design/DOC-DOCID_PLACEHOLDER_計画書.md) を参照\n"
    Open3.capture2 git_env, "git", "add", "README.md", chdir: @repo_root
    path = File.join @repo_root, "docs/design/DOC-DOCID_PLACEHOLDER_計画.md"
    File.write path,
               "# 計画\nDOC-DOCID_PLACEHOLDER_計画を参照。\n" \
               "[計画書](DOC-DOCID_PLACEHOLDER_計画書.md) を参照\n"
    Open3.capture2 git_env, "git", "add", "docs/design/DOC-DOCID_PLACEHOLDER_計画.md", chdir: @repo_root
    sibling = File.join @repo_root, "docs/design/DOC-DOCID_PLACEHOLDER_計画書.md"
    File.write sibling, "# 計画書\n"
    Open3.capture2 git_env, "git", "add", "docs/design/DOC-DOCID_PLACEHOLDER_計画書.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add files", chdir: @repo_root

    silence_stdout { @tool.assign "docs/design/DOC-DOCID_PLACEHOLDER_計画.md" }

    renamed = Dir.glob(File.join(@docs_dir, "design", "DOC-*_計画.md")).first
    content = File.read renamed
    # 助詞が直接続く省略形の自己参照は置換される
    assert_match(/DOC-\d{10}_計画を参照。/, content)
    # 計画書.md はまだ未採番なので、計画.md 自身の中の参照も書き換わらない
    assert_includes content, "DOC-DOCID_PLACEHOLDER_計画書.md"

    readme_content = File.read readme
    assert_includes readme_content, "DOC-DOCID_PLACEHOLDER_計画書.md"
  end

  def test_assign_leaves_unrelated_placeholder_mentions_in_self_file_unchanged
    path = File.join @repo_root, "docs/design/DOC-DOCID_PLACEHOLDER_計画.md"
    File.write path,
               "# 計画\n> **DOC-ID**: DOC-DOCID_PLACEHOLDER_計画\n\n" \
               "`DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` という名前で作り、" \
               "採番前は `DOC-DOCID_PLACEHOLDER` のままにする。\n\n" \
               "[別文書](../tracking/DOC-DOCID_PLACEHOLDER_未確定事項.md) も参照。\n"
    Open3.capture2 git_env, "git", "add", "docs/design/DOC-DOCID_PLACEHOLDER_計画.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add placeholder", chdir: @repo_root

    silence_stdout { @tool.assign "docs/design/DOC-DOCID_PLACEHOLDER_計画.md" }

    renamed = Dir.glob(File.join(@docs_dir, "design", "DOC-*_計画.md")).first
    content = File.read renamed

    # 自己参照（.md 無し）は新IDに置換される
    refute_includes content, "DOC-DOCID_PLACEHOLDER_計画"
    assert_match(/DOC-\d{10}_計画/, content)
    # 説明的ファイル名を伴わない裸の言及、命名規則の説明、他文書への参照は変わらない
    assert_includes content, "DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md"
    assert_includes content, "`DOC-DOCID_PLACEHOLDER`"
    assert_includes content, "DOC-DOCID_PLACEHOLDER_未確定事項.md"
  end

  def test_does_not_update_references_inside_excluded_test_directory
    test_dir = File.join @repo_root, "test"
    FileUtils.mkdir_p test_dir
    fixture = File.join test_dir, "fixture.md"
    File.write fixture, "DOC-DOCID_PLACEHOLDER_計画\n"
    Open3.capture2 git_env, "git", "add", "test/fixture.md", chdir: @repo_root
    path = File.join @repo_root, "docs/design/DOC-DOCID_PLACEHOLDER_計画.md"
    File.write path, "# 計画\n"
    Open3.capture2 git_env, "git", "add", "docs/design/DOC-DOCID_PLACEHOLDER_計画.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add files", chdir: @repo_root

    silence_stdout { @tool.assign "docs/design/DOC-DOCID_PLACEHOLDER_計画.md" }

    assert_includes File.read(fixture), "DOC-DOCID_PLACEHOLDER_計画"
  end

  # docs/spec/ は仕様書ディレクトリであり、除外対象にしてはならない。除外すると
  # iosci で実際に起きたとおり、参照更新が漏れる（実バグの regression）。
  def test_updates_references_inside_docs_spec_directory
    spec_dir = File.join @docs_dir, "spec"
    FileUtils.mkdir_p spec_dir
    fixture = File.join spec_dir, "fixture.md"
    File.write fixture, "DOC-DOCID_PLACEHOLDER_計画\n"
    Open3.capture2 git_env, "git", "add", "docs/spec/fixture.md", chdir: @repo_root
    path = File.join @repo_root, "docs/design/DOC-DOCID_PLACEHOLDER_計画.md"
    File.write path, "# 計画\n"
    Open3.capture2 git_env, "git", "add", "docs/design/DOC-DOCID_PLACEHOLDER_計画.md", chdir: @repo_root
    Open3.capture2 git_env, "git", "commit", "-m", "add files", chdir: @repo_root

    silence_stdout { @tool.assign "docs/design/DOC-DOCID_PLACEHOLDER_計画.md" }

    content = File.read fixture
    refute_includes content, "DOC-DOCID_PLACEHOLDER_計画"
    assert_match(/DOC-\d{10}_計画/, content)
  end

  def test_assigns_doc_id_matching_git_commit_date
    date_env = git_env.merge(
      "GIT_AUTHOR_DATE" => "2026-01-05T03:04:00+09:00",
      "GIT_COMMITTER_DATE" => "2026-01-05T03:04:00+09:00"
    )
    path = "docs/design/no_prefix.md"
    File.write File.join(@repo_root, path), "# Test\n"
    Open3.capture2 date_env, "git", "add", path, chdir: @repo_root
    Open3.capture2 date_env, "git", "commit", "-m", "add", chdir: @repo_root

    silence_stdout { @tool.assign path }

    renamed = Dir.glob File.join(@docs_dir, "design", "DOC-*_no_prefix.md")
    assert_equal 1, renamed.size
    assert_equal "DOC-2601050304_no_prefix.md", File.basename(renamed.first)
  end

  def test_assigns_suffixes_on_timestamp_collision
    date_env = git_env.merge(
      "GIT_AUTHOR_DATE" => "2026-02-10T09:00:00+09:00",
      "GIT_COMMITTER_DATE" => "2026-02-10T09:00:00+09:00"
    )
    %w[first second third].each do |name|
      path = "docs/design/#{name}.md"
      File.write File.join(@repo_root, path), "# #{name}\n"
      Open3.capture2 date_env, "git", "add", path, chdir: @repo_root
      Open3.capture2 date_env, "git", "commit", "-m", "add #{name}", chdir: @repo_root
      silence_stdout { @tool.assign path }
    end

    assert_equal 1, Dir.glob(File.join(@docs_dir, "design", "DOC-2602100900_first.md")).size
    assert_equal 1, Dir.glob(File.join(@docs_dir, "design", "DOC-2602100900-a_second.md")).size
    assert_equal 1, Dir.glob(File.join(@docs_dir, "design", "DOC-2602100900-b_third.md")).size
  end
end
