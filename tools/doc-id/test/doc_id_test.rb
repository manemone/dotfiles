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
    assert_equal(1, output.lines.count { |l| l.start_with? "❌" })
  end

  # docs/spec/ は仕様書ディレクトリであり、テストコードの spec/ とは違う。
  # 除外対象にすると、別のリポジトリのように壊れ参照を verify が見逃す（実バグの regression）。
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

  # 穴3: ID は実在するが説明的ファイル名が違う DOC-<ID>_<名前>.md を、インライン
  # コード・地の文・参照スタイルのリンク定義に書くと、旧実装では ID の実在しか見ず
  # 見逃していた（別のリポジトリで verify が 22 件のリンク切れを見逃した実バグ）。
  def test_detects_wrong_filename_in_inline_code
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"),
               "`docs/design/DOC-2606281807_別名.md` を参照。"
    silence_stdout { assert_equal 1, @tool.verify }
  end

  # 説明的ファイル名は中黒（・）や全角英数字を含みうる。Unicode の文字・数字
  # カテゴリだけで判定すると、中黒は句読点カテゴリのため除外され、ID は実在するが
  # ファイル名が違う参照を黙って見逃す（この検査が塞ぐべき穴1系のバグそのもの）。
  def test_detects_wrong_filename_containing_nakaguro_in_inline_code
    File.write File.join(@docs_dir, "design", "DOC-2606281807_技術・運用方針.md"), "# test"
    File.write File.join(@repo_root, "README.md"),
               "`docs/design/DOC-2606281807_設計・運用方針.md` を参照。"
    silence_stdout { assert_equal 1, @tool.verify }
  end

  def test_detects_wrong_filename_in_prose
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"),
               "docs/design/DOC-2606281807_別名.md に注意。"
    silence_stdout { assert_equal 1, @tool.verify }
  end

  def test_detects_wrong_filename_in_reference_style_link_definition
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"),
               "[test][t]\n\n[t]: docs/design/DOC-2606281807_別名.md\n"
    silence_stdout { assert_equal 1, @tool.verify }
  end

  def test_accepts_correct_filename_in_inline_code_and_reference_style_link
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"),
               "`docs/design/#{TEST_FILE}` と地の文 docs/design/#{TEST_FILE} を参照。\n\n" \
               "[test][t]\n\n[t]: docs/design/#{TEST_FILE}\n"
    silence_stdout { assert_equal 0, @tool.verify }
  end

  # .md で終わらない DOC-ID の言及は従来どおり ID の実在だけを見る
  # （説明的ファイル名の終わりを機械的に切り出せないため）。
  def test_id_only_mention_without_md_suffix_ignores_filename_mismatch
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"), "DOC-2606281807_別名 を参照。"
    silence_stdout { assert_equal 0, @tool.verify }
  end

  def test_does_not_double_report_wrong_filename_bare_ref
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"),
               "docs/design/DOC-2606281807_別名.md に注意。"
    output = capture_stdout { @tool.verify }
    assert_equal(1, output.lines.count { |l| l.start_with? "❌" })
  end

  # 長いファイル名を「...」で省略して言及する地の文（実在確認の対象外の書き方）を、
  # 実在しないファイルとして誤検知してはならない。ID自体は実在する前提
  # （実在しない場合は裸のID言及として従来どおり検出される。それとは別の観測）。
  def test_does_not_flag_ellipsis_abbreviated_mention
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"),
               "詳細は `DOC-2606281807_..._計画.md` 参照（孫3プロンプト §8 準拠）。"
    silence_stdout { assert_equal 0, @tool.verify }
  end

  # 命名規則そのものを説明する地の文の `<説明的ファイル名>` のようなプレースホルダを、
  # 実在しないファイルとして誤検知してはならない。ID自体は実在する前提
  # （実在しない場合は裸のID言及として従来どおり検出される。それとは別の観測）。
  def test_does_not_flag_generic_naming_convention_placeholder
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"),
               "新規ファイルは `DOC-2606281807_<説明的ファイル名>.md` で作る。"
    silence_stdout { assert_equal 0, @tool.verify }
  end

  # 拡張子なしの DOC-ID_名前 言及（ID の実在だけを見る書き方）の直後に、空白を挟まず
  # 全角括弧や読点で別の .md 言及が続くと、旧実装ではその境界を越えて1トークンとして
  # 誤って呑み込み、存在しない合成ファイル名として誤検知していた
  # （配布元のレビュー指摘。ブラックリスト方式で除外文字を挙げ漏れるたびに再発するため、
  # 実装は説明的ファイル名に実際に使われる文字種のアローリストへ変更した）。
  def test_does_not_merge_id_only_mention_with_following_unrelated_md_file
    File.write File.join(@docs_dir, "design", TEST_FILE), "# test"
    File.write File.join(@repo_root, "README.md"),
               "PR作法（DOC-2606281807_test）とAGENTS.mdを読む。"
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

  PLAN_PLACEHOLDER = "docs/design/DOC-DOCID_PLACEHOLDER_計画.md"
  PATH_STORE = "docs/design/DOC-DOCID_PLACEHOLDER_店舗情報.md"
  PATH_PENDING = "docs/tracking/DOC-DOCID_PLACEHOLDER_未確定事項.md"

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

  def git(*args, env: git_env) = Open3.capture2(env, "git", *args, chdir: @repo_root)

  # リポジトリ直下からの相対パスにファイルを書いて git add する。書いた絶対パスを返す。
  def stage(path, content)
    full = File.join @repo_root, path
    FileUtils.mkdir_p File.dirname(full)
    File.write full, content
    git "add", path
    full
  end

  def commit(message, env: git_env) = git("commit", "-m", message, env: env)

  def commit_file(path, content)
    stage path, content
    commit "add #{path}"
  end

  def assign_quietly(path) = silence_stdout { @tool.assign path }

  def assert_link_rewritten(content, old_placeholder, new_link_pattern)
    refute_includes content, old_placeholder
    assert_match new_link_pattern, content
  end

  def design_docs(pattern) = Dir.glob File.join(@docs_dir, "design", pattern)

  def test_assigns_doc_id_to_a_file_without_one
    commit_file "docs/design/no_prefix.md", "# Test\n"
    silence_stdout { assert_equal 0, @tool.assign("docs/design/no_prefix.md") }
    assert_equal 1, design_docs("DOC-*_no_prefix.md").size
  end

  def test_skips_file_with_proper_doc_id
    test_file = "DOC-2606281807_test.md"
    commit_file "docs/design/#{test_file}", "# Test\n"
    silence_stdout { assert_equal 0, @tool.assign("docs/design/#{test_file}") }
    assert File.exist?(File.join(@docs_dir, "design", test_file))
  end

  def test_does_not_treat_midnight_timestamp_as_placeholder
    legit_file = "docs/design/DOC-2607190000_設計.md"
    commit_file legit_file, "# 設計\n"
    silence_stdout { assert_equal 0, @tool.assign(legit_file) }
    assert File.exist?(File.join(@repo_root, legit_file))
  end

  def test_placeholder_file_renamed_and_content_replaced
    commit_file PLAN_PLACEHOLDER, "# 計画\n> **DOC-ID**: DOC-DOCID_PLACEHOLDER_計画\n"

    assign_quietly PLAN_PLACEHOLDER

    renamed = design_docs "DOC-*_計画.md"
    assert_equal 1, renamed.size
    refute_includes File.basename(renamed.first), "DOCID_PLACEHOLDER"

    content = File.read renamed.first
    refute_includes content, "DOC-DOCID_PLACEHOLDER"
    assert_match(/DOC-\d{6}\d{4}/, content)
  end

  def test_updates_references_across_multiple_file_types_and_locations
    readme = stage "README.md", "[計画](docs/design/DOC-DOCID_PLACEHOLDER_計画.md) と DOC-DOCID_PLACEHOLDER\n"
    sh_file = stage "shared/helpers.sh", "# 設計は DOC-DOCID_PLACEHOLDER_計画 を参照\n"
    yml_file = stage "examples/conf.yml", "doc: DOC-DOCID_PLACEHOLDER_計画\n"
    md_file = stage "examples/README.md", "see DOC-DOCID_PLACEHOLDER_計画\n"
    commit_file PLAN_PLACEHOLDER, "# 計画\n> **DOC-ID**: DOC-DOCID_PLACEHOLDER_計画\n"

    assign_quietly PLAN_PLACEHOLDER

    assert_match %r{\[計画\]\(docs/design/DOC-\d{10}_計画\.md\) と DOC-DOCID_PLACEHOLDER}, File.read(readme)
    assert_match(/# 設計は DOC-\d{10}_計画 を参照/, File.read(sh_file))
    assert_match(/doc: DOC-\d{10}_計画/, File.read(yml_file))
    assert_match(/see DOC-\d{10}_計画/, File.read(md_file))
  end

  def test_preserves_suffix_bearing_doc_ids_and_replaces_only_document_reference
    readme = stage "README.md", "DOC-DOCID_PLACEHOLDER_計画 と DOC-DOCID_PLACEHOLDER と DOC-DOCID_PLACEHOLDER-a の比較\n"
    commit_file PLAN_PLACEHOLDER, "# 計画\n"

    assign_quietly PLAN_PLACEHOLDER

    content = File.read readme
    assert_includes content, "DOC-DOCID_PLACEHOLDER-a"
    assert_match(/DOC-\d{10}_計画/, content)
    assert_includes content, "DOC-DOCID_PLACEHOLDER と"
  end

  def stage_cross_linked_pair
    stage PATH_STORE, "# 店舗情報\n[未確定事項](../tracking/DOC-DOCID_PLACEHOLDER_未確定事項.md)\n"
    stage PATH_PENDING, "# 未確定事項\n[店舗情報](../design/DOC-DOCID_PLACEHOLDER_店舗情報.md)\n"
    commit "add A and B"
  end

  def test_assigning_one_placeholder_does_not_corrupt_link_to_another_placeholder_document
    stage_cross_linked_pair

    assign_quietly PATH_STORE

    # 穴1: Bはまだ未採番なので、Bへのプレースホルダ参照は書き換わらず残る
    assert_includes File.read(design_docs("DOC-*_店舗情報.md").first), "DOC-DOCID_PLACEHOLDER_未確定事項.md"
    assert_link_rewritten File.read(File.join(@repo_root, PATH_PENDING)), "DOC-DOCID_PLACEHOLDER_店舗情報",
                          %r{\.\./design/DOC-\d{10}_店舗情報\.md}
  end

  def test_assigning_the_second_placeholder_rewrites_the_link_left_in_the_first
    stage_cross_linked_pair
    assign_quietly PATH_STORE
    git "add", "-A"
    commit "assign a"

    assign_quietly PATH_PENDING

    assert_link_rewritten File.read(design_docs("DOC-*_店舗情報.md").first), "DOC-DOCID_PLACEHOLDER",
                          %r{\.\./tracking/DOC-\d{10}(?:-[a-z])?_未確定事項\.md}
  end

  def test_assign_does_not_corrupt_placeholder_link_to_document_whose_name_shares_a_prefix
    readme = stage "README.md", "[計画書](docs/design/DOC-DOCID_PLACEHOLDER_計画書.md) を参照\n"
    stage PLAN_PLACEHOLDER,
          "# 計画\nDOC-DOCID_PLACEHOLDER_計画を参照。\n" \
          "[計画書](DOC-DOCID_PLACEHOLDER_計画書.md) を参照\n"
    stage "docs/design/DOC-DOCID_PLACEHOLDER_計画書.md", "# 計画書\n"
    commit "add files"

    assign_quietly PLAN_PLACEHOLDER

    content = File.read design_docs("DOC-*_計画.md").first
    # 助詞が直接続く省略形の自己参照は置換される
    assert_match(/DOC-\d{10}_計画を参照。/, content)
    # 計画書.md はまだ未採番なので、計画.md 自身の中の参照も書き換わらない
    assert_includes content, "DOC-DOCID_PLACEHOLDER_計画書.md"
    assert_includes File.read(readme), "DOC-DOCID_PLACEHOLDER_計画書.md"
  end

  def test_assign_leaves_unrelated_placeholder_mentions_in_self_file_unchanged
    commit_file PLAN_PLACEHOLDER,
                "# 計画\n> **DOC-ID**: DOC-DOCID_PLACEHOLDER_計画\n\n" \
                "`DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md` という名前で作り、" \
                "採番前は `DOC-DOCID_PLACEHOLDER` のままにする。\n\n" \
                "[別文書](../tracking/DOC-DOCID_PLACEHOLDER_未確定事項.md) も参照。\n"

    assign_quietly PLAN_PLACEHOLDER

    content = File.read design_docs("DOC-*_計画.md").first

    # 自己参照（.md 無し）は新IDに置換される
    refute_includes content, "DOC-DOCID_PLACEHOLDER_計画"
    assert_match(/DOC-\d{10}_計画/, content)
    # 説明的ファイル名を伴わない裸の言及、命名規則の説明、他文書への参照は変わらない
    assert_includes content, "DOC-DOCID_PLACEHOLDER_<説明的ファイル名>.md"
    assert_includes content, "`DOC-DOCID_PLACEHOLDER`"
    assert_includes content, "DOC-DOCID_PLACEHOLDER_未確定事項.md"
  end

  def test_does_not_update_references_inside_excluded_test_directory
    fixture = stage "test/fixture.md", "DOC-DOCID_PLACEHOLDER_計画\n"
    commit_file PLAN_PLACEHOLDER, "# 計画\n"

    assign_quietly PLAN_PLACEHOLDER

    assert_includes File.read(fixture), "DOC-DOCID_PLACEHOLDER_計画"
  end

  # docs/spec/ は仕様書ディレクトリであり、除外対象にしてはならない。除外すると
  # 別のリポジトリで実際に起きたとおり、参照更新が漏れる（実バグの regression）。
  def test_updates_references_inside_docs_spec_directory
    fixture = stage "docs/spec/fixture.md", "DOC-DOCID_PLACEHOLDER_計画\n"
    commit_file PLAN_PLACEHOLDER, "# 計画\n"

    assign_quietly PLAN_PLACEHOLDER

    content = File.read fixture
    refute_includes content, "DOC-DOCID_PLACEHOLDER_計画"
    assert_match(/DOC-\d{10}_計画/, content)
  end

  def test_assigns_doc_id_matching_git_commit_date
    path = "docs/design/no_prefix.md"
    stage path, "# Test\n"
    commit "add", env: dated_git_env("2026-01-05T03:04:00+09:00")

    assign_quietly path

    renamed = design_docs "DOC-*_no_prefix.md"
    assert_equal 1, renamed.size
    assert_equal "DOC-2601050304_no_prefix.md", File.basename(renamed.first)
  end

  def test_assigns_suffixes_on_timestamp_collision
    date_env = dated_git_env "2026-02-10T09:00:00+09:00"

    %w[first second third].each do |name|
      path = "docs/design/#{name}.md"
      stage path, "# #{name}\n"
      commit "add #{name}", env: date_env
      assign_quietly path
    end

    %w[DOC-2602100900_first.md DOC-2602100900-a_second.md DOC-2602100900-b_third.md].each do |expected|
      assert_equal 1, design_docs(expected).size
    end
  end

  private

  def dated_git_env(iso8601) = git_env.merge("GIT_AUTHOR_DATE" => iso8601, "GIT_COMMITTER_DATE" => iso8601)
end
