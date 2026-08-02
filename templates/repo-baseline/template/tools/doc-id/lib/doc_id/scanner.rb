# frozen_string_literal: true

require "open3"

module DocId
  # File scanning, fence parsing, and reference verification.
  # Mixed into DocId::Tool; accesses @repo_root / @docs_dir from there.
  module Scanner
    private

    def collect_violations
      violations = []
      Dir.glob(File.join(@docs_dir, "**", "*.md")).each do |file|
        basename = File.basename file
        next if README_PATTERN.match? basename

        rel = relative_path file
        if placeholder_doc_id? basename
          violations << { file: rel, reason: "プレースホルダ未割当" }
        elsif !PATTERN.match?(basename)
          violations << { file: rel, reason: "DOC-XXX プレフィクスなし" }
        end
      end
      violations
    end

    def find_broken_refs
      broken = []
      # test/ tests/ spec/ を除外（テストフィクスチャに意図的な壊れ参照が含まれるため）
      searchable_files.reject { |f| excluded_path? f }.each do |file|
        content = File.read file
        rel = relative_path file
        # Match: [text](path/to/DOC-XXX_...md) or bare DOC-XXX
        check_md_links content, rel, broken
        check_bare_refs content, rel, broken
      rescue Errno::ENOENT
        # File is tracked in the index but missing from the working tree
        # (e.g., deleted with rm instead of git rm). Skip it.
      end
      broken
    end

    # Returns a line iterator that skips code fences (supports nested fences by
    # tracking the opening marker length).
    def each_outside_fence(content)
      return enum_for :each_outside_fence, content unless block_given?

      fence_len = nil
      fence_indent = nil
      content.each_line.with_index 1 do |line, num|
        if (m = line.match(/^(\s*)(`{3,})/))
          fence_len, fence_indent = fence_transition m, fence_len, fence_indent
          next
        end
        next if fence_len

        yield line, num
      end
    end

    # Returns [new_len, new_indent] after processing a fence marker line.
    # A fence with info string (e.g. ```yaml) at the same indent is treated as
    # opening a nested fence, not closing the outer one.
    def fence_transition(match, flen, findent)
      indent = match[1].length
      len = match[2].length
      info = match.post_match.strip
      if flen.nil?
        [len, indent]
      elsif len >= flen && indent <= (findent || 0) && info.empty?
        [nil, nil]
      else
        [flen, findent]
      end
    end

    def check_md_links(content, rel, broken)
      each_outside_fence content do |line, num|
        line.scan(/\[[^\]]*\]\(([^)]*DOC-\d{6}\d{4}[^)]*)\)/).each do |match|
          target = match[0]
          next if target.start_with? "http"

          src_dir = File.dirname File.join(@repo_root, rel)
          resolved = File.expand_path target, src_dir
          broken << { file: rel, ref: target, line: num } unless File.exist? resolved
        end
      end
    end

    def check_bare_refs(content, rel, broken)
      each_outside_fence content do |line, num|
        # マークダウンリンクの target 部分は check_md_links が別途検証するため、
        # ここでは除外する（DOC-<10桁>_<ファイル名> 形式のリンク先を二重報告しないため）。
        scrubbed = line.gsub(/\[[^\]]*\]\([^)]*\)/) { |m| " " * m.length }
        scrubbed.scan(/\b(DOC-\d{6}\d{4}(?:-[a-z])?)(?=_|\b)/).each do |match|
          id = match[0]
          broken << { file: rel, ref: id, line: num } unless doc_id_exists? id
        end
      end
    end

    def doc_id_exists?(id) = !Dir.glob(File.join(@docs_dir, "**", "#{id}_*")).empty?

    def searchable_files
      git_tracked_files.select { |f| searchable_file? f }
    end

    def searchable_file?(f)
      SEARCHABLE_EXTENSIONS.any? { |ext| f.end_with? ext } || extensionless_shebang_script?(f)
    end

    # 拡張子なしの実行ファイル（bin/ocw 等）は shebang の有無で判定する。
    # 拡張子を持つファイル（.rb 等、意図的に SEARCHABLE_EXTENSIONS から除外しているもの）は対象にしない。
    def extensionless_shebang_script?(f)
      return false unless File.extname(f).empty?

      File.open(f, "rb") { |io| io.read(2) } == "#!"
    rescue Errno::ENOENT, IOError
      false
    end

    # @repo_root からの相対パスのディレクトリ成分単位で判定する。絶対パス全体に対する
    # 部分一致だと、リポジトリ自体が test/ 等を含むパスに置かれた場合に誤爆する。
    def excluded_path?(path)
      relative_path(path).split("/").any? { |seg| EXCLUDED_DIR_NAMES.include? seg }
    end

    def git_tracked_files
      # Clear git env vars inherited from pre-commit/git-hook context so that
      # git ls-files runs against @repo_root, not the parent process's repo.
      # Use -z for NUL-delimited output to avoid core.quotePath escaping of
      # non-ASCII paths (e.g., Japanese filenames).
      env = { "GIT_DIR" => nil, "GIT_WORK_TREE" => nil, "GIT_INDEX_FILE" => nil }
      result, status = Open3.capture2 env, "git", "ls-files", "--cached", "-z", chdir: @repo_root
      unless status.success?
        # Fall back to glob scan when not in a git repo (e.g., unit tests with temp dirs).
        # Exclude .git/ in case a real .git directory exists alongside the scan root.
        ext_pattern = SEARCHABLE_EXTENSIONS.map { |e| e.delete_prefix "." }.join(",")
        return Dir.glob(
          File.join(@repo_root, "**", "*.{#{ext_pattern}}"),
          File::FNM_DOTMATCH
        ).reject { |f| f.include? "/.git/" }
      end

      result.split("\0").map { |f| File.join @repo_root, f.strip }.reject { |f| f == @repo_root.to_s }
    end

    def relative_path(abs_path) = abs_path.sub(%r{\A#{Regexp.escape @repo_root}/}, "")
  end
end
