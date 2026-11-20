# Bounded walk over the user's KB sources: projects, folders, files and note text matching a query.
module KbEntrySearch
  extend ActiveSupport::Concern

  SEARCH_LIMIT = 30
  SEARCH_VISIT_CAP = 5000 # ponytail: bounded walk, index if KBs outgrow this
  DEEP_EXT = %w[.md .markdown .txt .vtt].freeze
  DEEP_FILE_BYTES = 256.kilobytes

  private

  INDEX_TTL = 1.hour # safety net only; KB writes bump the generation below

  # Where an entry opens: a file is a document, a project its page, a plain folder the KB with the tree revealed there.
  # (kb_path(file:) only resolves files, so folders/projects built that way 404 as "missing".)
  def kb_entry_url(e)
    case e[:type]
    when "project" then kb_path(src: e[:src], project: e[:path])
    when "dir" then kb_path(src: e[:src], folder: e[:path])
    else kb_path(src: e[:src], file: e[:path])
    end
  end

  # Filters the cached walk in memory: typing never re-walks the disk.
  def search_entries(query)
    found = kb_entry_index.filter_map do |e|
      next unless e[:rel_down].include?(query) || (!query.empty? && e[:note_down].include?(query))
      next if query.empty? && e[:type] != "project"

      e.merge(rank: [ { "project" => 0, "dir" => 1, "file" => 2 }[e[:type]], e[:name_down].include?(query) ? 0 : 1 ])
    end
    found.sort_by { |e| e[:rank] }.first(SEARCH_LIMIT).map { |e| e.slice(:src, :path, :name, :type, :source) }
  end

  # Keyed on the KB tree generation: every KB write already calls Kb::TreeBuilder.bust_cache!, which invalidates this.
  def kb_entry_index
    key = [ "kb_entry_index", @user.id, Kb::TreeBuilder.cache_generation(@user.id), KbSource.list(@user).map { |s| s[:path] } ]
    Rails.cache.fetch(key, expires_in: INDEX_TTL) { walk_kb_entries }
  end

  def walk_kb_entries
    found = []
    @walk_capped = [] # source indexes whose walk stopped at the visit cap (entries beyond it were never seen)
    KbSource.list(@user).each_with_index do |source, index|
      base = File.expand_path(source[:path])
      next unless File.directory?(base)

      visited = 0 # per source so one big KB can't starve the others

      queue = [ "" ]
      until queue.empty? || visited > SEARCH_VISIT_CAP
        dir = queue.shift
        children(File.join(base, dir)).each do |name|
          next if name.start_with?(".")

          visited += 1
          rel = dir.empty? ? name : "#{dir}/#{name}"
          abs = File.join(base, rel)
          next if File.symlink?(abs) || Kb::Note.sidecar?(name) || Kb::Source.sidecar?(name) # the note rides on its file's row

          is_dir = File.directory?(abs)
          project = Kb::Project.at(base, rel) if is_dir
          queue << rel if is_dir && !project&.locked? # locked projects stay behind the lock

          found << { src: index, path: rel, name: name, type: is_dir ? (project ? "project" : "dir") : "file", source: source[:label],
                     rel_down: rel.downcase, name_down: name.downcase, note_down: is_dir ? "" : Kb::Note.read(abs).to_s.downcase }
        end
      end
      @walk_capped << index unless queue.empty?
    end
    found
  end

  # First `bytes` of a text-ish KB file ("" for anything else or unreadable).
  def kb_file_text(entry, bytes)
    return "" unless entry[:type] == "file" && DEEP_EXT.include?(File.extname(entry[:name]).downcase)

    File.read(File.join(File.expand_path(KbSource.list(@user)[entry[:src]][:path]), entry[:path]), bytes).to_s.scrub
  rescue SystemCallError
    ""
  end

  def children(dir)
    Dir.children(dir).sort
  rescue SystemCallError
    []
  end
end
