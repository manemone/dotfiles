# frozen_string_literal: true

require "open3"
require "fileutils"

module DocId
  # 参照検証の走査対象ディレクトリ名。孫6でテンプレート変数化する際にここだけ差し替える想定
  DOCS_DIR_NAME = "docs"
  # テストフィクスチャに意図的な壊れ参照が含まれうるため、参照検証・参照更新の対象から除外するディレクトリ名
  EXCLUDED_DIR_NAMES = %w[test tests spec].freeze
  # 参照を書きうる設定・スクリプトの拡張子。.md は必須。他は dotfiles の実態（deploy.sh 等のシェル
  # スクリプト、CI/設定ファイル）に合わせて選定した。Ruby は tools/ 配下のツール実装にのみ存在し、
  # そこに DOC-ID 参照を書かない運用とするため対象外（.rb を含めると verify/assign の対象になる）
  SEARCHABLE_EXTENSIONS = %w[.md .sh .yml .yaml .json].freeze

  PATTERN = /\ADOC-(?:\d{6}\d{4}|DOCID_PLACEHOLDER)(?:-[a-z])?_.+\.md\z/
  README_PATTERN = /\AREADME\.md\z/
end

require_relative "scanner"

module DocId
  class Tool
    include Scanner
    def initialize(repo_root: nil)
      @repo_root = repo_root || find_repo_root
      @docs_dir = File.join @repo_root, DOCS_DIR_NAME
    end

    # check: 全 docs/ ファイルが命名規則に従っているか検証
    def check(*)
      violations = collect_violations
      return 0 if violations.empty?

      violations.each { |v| puts "❌ #{v[:file]}: #{v[:reason]}" }
      puts "\n#{violations.size}件の違反があります。tools/doc-id/doc-id assign <file> で修正してください。"
      1
    end

    # verify: 全ファイル内の DOC-XXX 参照先が実在するか検証
    def verify
      broken = find_broken_refs
      return 0 if broken.empty?

      broken.each do |b|
        puts "❌ #{b[:file]}:#{b[:line]}: #{b[:ref]} → 実在しません"
      end
      puts "\n#{broken.size}件の切れ参照があります。"
      1
    end

    # assign: git log から作成日時を取得し DOC-ID を割り当て
    # プレースホルダ（DOC-DOCID_PLACEHOLDER）が検出された場合は
    # 実際のタイムスタンプで再採番し、リポジトリ全体の参照も更新する。
    def assign(file_path)
      abs_path = File.expand_path file_path, @repo_root
      return missing_file_error file_path unless File.exist? abs_path

      basename = File.basename abs_path
      old_doc_id = resolve_old_doc_id abs_path, basename
      return 0 if old_doc_id == :skip

      doc_id = generate_doc_id get_first_commit_time(abs_path), abs_path
      clean = basename.sub(/\A(\d{2}_|DOC-(?:\d{6}\d{4}|DOCID_PLACEHOLDER)(?:-[a-z])?_)?/, "")
      rename_with_content_replacement abs_path, doc_id, old_doc_id, clean
      replace_all_doc_id_refs old_doc_id, doc_id, clean
      0
    end

    private

    def missing_file_error(file_path)
      puts "エラー: #{file_path} が見つかりません"
      1
    end

    def find_repo_root
      result, status = Open3.capture2 "git", "rev-parse", "--show-toplevel"
      raise "Not in a git repository" unless status.success?

      result.strip
    end

    def get_first_commit_time(file_path)
      # pre-commit/git-hook context から継承した GIT_DIR 等をクリアし、@repo_root を
      # 明示的な作業ディレクトリにする。git_tracked_files (scanner.rb) と同じ理由。
      env = { "GIT_DIR" => nil, "GIT_WORK_TREE" => nil, "GIT_INDEX_FILE" => nil }
      result, status = Open3.capture2 \
        env, "git", "log", "--follow", "--diff-filter=A", "--format=%aI", "--", file_path,
        chdir: @repo_root
      return now_stamp unless status.success?

      parse_iso8601 result.strip.split("\n").last
    end

    def now_stamp = Time.now.strftime("%y%m%d%H%M")

    def parse_iso8601(str)
      return now_stamp if str.nil? || str.empty?

      m = str.match(/^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/)
      m ? "#{m[1][2, 2]}#{m[2]}#{m[3]}#{m[4]}#{m[5]}" : now_stamp
    end

    def generate_doc_id(timestamp, _file_path)
      base_id = "DOC-#{timestamp}"
      return base_id if no_collision? base_id

      "#{base_id}-#{next_suffix base_id}"
    end

    def no_collision?(base_id) = Dir.glob(File.join(@docs_dir, "**", "#{base_id}*")).empty?

    def next_suffix(base_id)
      used = Dir.glob(File.join(@docs_dir, "**", "#{base_id}*")).map do |f|
        m = File.basename(f).match(/\A#{Regexp.escape base_id}(?:-([a-z]))?_/)
        m ? (m[1] || "") : ""
      end
      # 同一分単位のコミットが27件以上衝突するのは想定外のため、その場合は "z" を
      # 使い回す（重複 DOC-ID が生じうる）。1分間に27件の新規文書は非現実的と判断した
      ("a".."z").find { |c| !used.include?(c) } || "z"
    end

    # ファイル名から既存 DOC-ID の状態を判定する
    # Returns: old DOC-ID string (プレースホルダ), nil (DOC-IDなし), :skip (適切なDOC-ID付与済)
    def resolve_old_doc_id(abs_path, basename)
      return nil unless PATTERN.match? basename

      if placeholder_doc_id? basename
        basename.match(/\A(DOC-DOCID_PLACEHOLDER)/)&.[](1)
      else
        puts "スキップ: #{relative_path abs_path} (すでに適切なDOC-IDが付与されています)"
        :skip
      end
    end

    # DOC-DOCID_PLACEHOLDER をプレースホルダと判定（正規の DOC-ID と衝突しない予約リテラル）
    def placeholder_doc_id?(basename)
      basename.start_with? "DOC-DOCID_PLACEHOLDER_"
    end

    def rename_with_content_replacement(abs_path, doc_id, old_doc_id, clean)
      if old_doc_id && (content = File.read abs_path) && content.include?(old_doc_id)
        File.write abs_path, content.gsub(/#{Regexp.escape old_doc_id}(?!-[\da-z])/, doc_id)
      end
      new_path = File.join File.dirname(abs_path), "#{doc_id}_#{clean}"
      FileUtils.mv abs_path, new_path
      puts "割当: #{relative_path abs_path} → #{relative_path new_path}"
    end

    def replace_all_doc_id_refs(old_id, new_id, clean_name)
      unless old_id
        puts "  参照更新は行いません。旧ファイル名への参照を git grep で確認してください"
        return
      end

      ref_full = "#{old_id}_#{clean_name}"
      ref_bare = "#{old_id}_#{clean_name.delete_suffix '.md'}"
      searchable_files.reject { |f| excluded_path? f }.each do |file|
        content = File.read file
        next unless content.include?(ref_full) || content.include?(ref_bare)

        content = content.gsub(ref_full, "#{new_id}_#{clean_name}")
                         .gsub ref_bare, "#{new_id}_#{clean_name.delete_suffix '.md'}"
        File.write file, content
        puts "  参照更新: #{relative_path file}"
      rescue Errno::ENOENT
        # Skip renamed file's old path.
      end
    end
  end
end
