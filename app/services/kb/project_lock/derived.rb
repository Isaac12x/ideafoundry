require "find"

module Kb
  module ProjectLock
    # Everything derived from a project's files that lives OUTSIDE the project
    # folder: media-edit revisions (<root>/.ideafoundry-history/<project>/), DB
    # text copies (annotation quotes, video transcripts + digests, long-OCR
    # markdown + errors, fs-job prompts/transcripts, download reference lists,
    # queued media-edit replacement blobs) and cached image OCR (storage/kb_ocr).
    # On lock these are written into the project folder (so they ride inside the
    # encrypted archive) and then removed from the app; on unlock they are put back.
    # Left alone (names/urls/paths only, no file content): kb_entry_preferences,
    # kb_links/idea_kb_links, kb_downloads url/title/filename, kb_media_edits rows,
    # tree cache (names only, busted by the caller). Not covered: fs-job voice
    # attachments (Active Storage), whisper state files (error text only).
    module Derived
      FILE = ".lock-derived.json".freeze
      HISTORY = ".lock-history".freeze
      ACTIVE = %w[pending running].freeze

      module_function

      def history_dir(base, rel) = File.join(File.expand_path(base), ".ideafoundry-history", rel)

      def inside?(rel, path)
        path = path.to_s.sub(%r{\A/+}, "")
        path == rel || path.start_with?("#{rel}/")
      end

      def downloads(user, project)
        base = File.expand_path(project.base)
        user.kb_downloads.where(source_path: base).select { |d| inside?(project.rel, File.join(d.dir.to_s, d.filename.to_s)) || inside?(project.rel, d.dir) }
      end

      def extractions(project)
        prefix = "#{project.abs}/"
        KnowledgeExtraction.where(source_kind: KnowledgeExtraction::KB_FILE).select { |e| e.kb_path.to_s.start_with?(prefix) }
      end

      def media_edits(user, project)
        user.kb_media_edits.where(source_path: File.expand_path(project.base)).select { |e| inside?(project.rel, e.relative_path) }
      end

      def fs_jobs(user, project)
        user.kb_fs_jobs.where(source_path: File.expand_path(project.base)).select { |j| inside?(project.rel, j.context_path) || inside?(project.rel, j.target_dir) }
      end

      # Anything still writing into the project: downloads, transcripts (captions or
      # whisper), media edits, fs jobs.
      def active_work?(user, project)
        media = Dir.glob(File.join(project.abs, "**", "*")).any? { |f| File.file?(f) && Transcript.media?(f) && Transcript.running?(f) }
        return true if media
        return false unless user

        downloads(user, project).any? { |d| ACTIVE.include?(d.status) || %w[pending transcribing].include?(d.transcript_status) } ||
          media_edits(user, project).any? { |e| ACTIVE.include?(e.status) } ||
          fs_jobs(user, project).any? { |j| ACTIVE.include?(j.status) }
      end

      # The plaintext that leaves the app, as plain JSON-able data (ids included, so
      # scrub! removes exactly this and verify! can tell if anything changed since).
      def collect(project, user)
        data = { "project_rel" => project.rel, "annotations" => [], "bookmarks" => [], "downloads" => {}, "digests" => [], "extractions" => {},
                 "references" => {}, "extraction_errors" => {}, "fs_jobs" => {} }
        return data unless user

        base = File.expand_path(project.base)
        data["annotations"] = user.kb_annotations.where(source_path: base).select { |a| inside?(project.rel, a.relative_path) }.map(&:attributes)
        data["bookmarks"] = user.kb_bookmarks.where(source_path: base).select { |b| inside?(project.rel, b.relative_path) }.map(&:attributes)
        dls = downloads(user, project)
        data["downloads"] = dls.select { |d| d.transcript.present? }.to_h { |d| [ d.id, d.transcript ] }
        data["references"] = dls.select { |d| d.reference_list.present? }.to_h { |d| [ d.id, d.reference_list ] }
        data["digests"] = MediaDigest.where(kb_download_id: dls.map(&:id)).map(&:attributes)
        exts = extractions(project)
        data["extractions"] = exts.select { |e| e.markdown.present? }.to_h { |e| [ e.id, e.markdown ] }
        data["extraction_errors"] = exts.select { |e| e.error.present? }.to_h { |e| [ e.id, e.error ] }
        data["fs_jobs"] = fs_jobs(user, project).select { |j| j.prompt.present? || j.transcript.present? }
                                                 .to_h { |j| [ j.id, { "prompt" => j.prompt, "transcript" => j.transcript } ] }
        JSON.parse(JSON.generate(data))
      end

      # Plaintext copies go next to the project files; the DB/history are untouched until scrub!.
      # Returns the stashed data.
      def stash!(project, user, abs)
        data = collect(project, user)
        File.write(File.join(abs, FILE), JSON.generate(data))
        hist = history_dir(project.base, project.rel)
        FileUtils.cp_r(hist, File.join(abs, HISTORY), preserve: true) if File.directory?(hist)
        data
      end

      # Raises when any stashed row changed or a new one appeared since stash!: the
      # archive would miss it (or scrub! would destroy it).
      def verify!(project, user, data)
        return if collect(project, user) == data

        raise Error, "Changes happened while locking, try again."
      end

      def discard_stash(abs)
        FileUtils.rm_rf([ File.join(abs, FILE), File.join(abs, HISTORY) ])
      end

      # After the archive is committed: drop exactly the stashed DB plaintext (by id;
      # rows created later are untouched). File/history copies are removed by the caller.
      def scrub!(project, user, data)
        return unless user

        ActiveRecord::Base.transaction do
          user.kb_annotations.where(id: data["annotations"].map { |a| a["id"] }).destroy_all
          user.kb_bookmarks.where(id: Array(data["bookmarks"]).map { |b| b["id"] }).delete_all
          MediaDigest.where(id: data["digests"].map { |d| d["id"] }).delete_all
          user.kb_downloads.where(id: data["downloads"].keys | data["references"].keys).each do |d|
            d.update_columns(transcript: nil, reference_list: [])
          end
          KnowledgeExtraction.where(id: data["extractions"].keys | data["extraction_errors"].keys).each do |e|
            e.update_columns(markdown: nil, error: nil)
          end
          user.kb_fs_jobs.where(id: data["fs_jobs"].keys).each { |j| j.update_columns(prompt: nil, transcript: nil) }
          media_edits(user, project).each { |e| e.replacement_file.purge if e.replacement_file.attached? }
        end
      end

      # Cached image OCR text of the project's images (storage/kb_ocr). Call while the files still exist.
      def purge_ocr(abs)
        ImageOcr.purge!(abs)
      rescue StandardError => e
        Rails.logger.error("ProjectLock OCR purge: #{e.class}: #{e.message}")
      end

      # from = extracted dir holding FILE / HISTORY. Idempotent: existing rows/files are kept.
      # Every section is independent and failures only log, so a bad row never blocks the
      # file restore (unlock must not get stuck).
      def restore!(project, user, from)
        file = File.join(from, FILE)
        if user && File.file?(file)
          data = begin
            JSON.parse(File.read(file))
          rescue JSON::ParserError => e
            Rails.logger.error("ProjectLock restore: #{e.message}")
            {}
          end
          restore_sections(project, user, data)
        end
        stash = File.join(from, HISTORY)
        return unless File.directory?(stash)

        FileUtils.mkdir_p(hist = history_dir(project.base, project.rel))
        merge_dir(stash, hist)
      end

      def restore_sections(project, user, data)
        guarded("annotations") do
          # The folder may have been renamed/moved while locked: follow its current path.
          old = data["project_rel"].presence || project.rel
          rows = Array(data["annotations"]).map do |a|
            rest = a["relative_path"].to_s.delete_prefix(old)
            a.merge("relative_path" => "#{project.rel}#{rest}")
          end
          KbAnnotation.insert_all(rows) if rows.any?
        end
        guarded("bookmarks") do
          old = data["project_rel"].presence || project.rel
          rows = Array(data["bookmarks"]).map { |b| b.merge("relative_path" => "#{project.rel}#{b["relative_path"].to_s.delete_prefix(old)}") }
          KbBookmark.insert_all(rows) if rows.any?
        end
        guarded("downloads") do
          alive = user.kb_downloads.where(id: [ *data["downloads"]&.keys, *data["references"]&.keys, *Array(data["digests"]).map { |d| d["kb_download_id"] } ]).pluck(:id)
          user.kb_downloads.where(id: data["downloads"]&.keys).each { |d| d.update_columns(transcript: data["downloads"][d.id.to_s]) }
          user.kb_downloads.where(id: data["references"]&.keys).each { |d| d.update_columns(reference_list: data["references"][d.id.to_s]) }
          digests = Array(data["digests"]).select { |d| alive.include?(d["kb_download_id"]) }
          MediaDigest.insert_all(digests) if digests.any?
        end
        guarded("extractions") do
          KnowledgeExtraction.where(id: data["extractions"]&.keys).each { |e| e.update_columns(markdown: data["extractions"][e.id.to_s]) }
          KnowledgeExtraction.where(id: data["extraction_errors"]&.keys).each { |e| e.update_columns(error: data["extraction_errors"][e.id.to_s]) }
        end
        guarded("fs_jobs") do
          user.kb_fs_jobs.where(id: data["fs_jobs"]&.keys).each { |j| j.update_columns(**data["fs_jobs"][j.id.to_s].symbolize_keys.slice(:prompt, :transcript)) }
        end
      end

      def guarded(name)
        ActiveRecord::Base.transaction { yield }
      rescue StandardError => e
        Rails.logger.error("ProjectLock restore #{name}: #{e.class}: #{e.message}")
      end

      # Moves children of src into dst, never overwriting (existing keeps its name).
      def merge_dir(src, dst)
        Dir.children(src).each do |name|
          from = File.join(src, name)
          to = File.join(dst, name)
          if File.directory?(from) && File.directory?(to) && !File.symlink?(to)
            merge_dir(from, to)
          elsif !File.exist?(to) && !File.symlink?(to)
            FileUtils.mv(from, to)
          end
        end
      end

      # { rel => signature } of everything under root (root excluded). Dirs ignore mtime.
      def snapshot(root)
        snap = {}
        return snap unless File.directory?(root)

        Find.find(root) do |path|
          next if path == root

          st = File.lstat(path)
          snap[path.delete_prefix("#{root}/")] = st.directory? ? [ :dir ] : [ st.ftype, st.size, st.mtime.to_r ]
        end
        snap
      end

      # Deletes exactly the snapshotted entries that still look the same; anything
      # new or modified since the snapshot stays. Dirs go only when empty.
      def remove_snapshot(root, snap, except: [])
        files, dirs = snap.partition { |_, sig| sig != [ :dir ] }
        files.each do |rel, sig|
          next if except.include?(rel)

          path = File.join(root, rel)
          File.delete(path) if File.lstat(path).then { |st| [ st.ftype, st.size, st.mtime.to_r ] == sig }
        rescue Errno::ENOENT
          nil
        end
        dirs.map(&:first).sort_by { |rel| -rel.count("/") }.each do |rel|
          Dir.rmdir(File.join(root, rel))
        rescue SystemCallError
          nil
        end
      end
    end
  end
end
