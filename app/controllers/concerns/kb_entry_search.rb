# Bounded walk over the user's KB sources: projects, folders, files and note text matching a query.
module KbEntrySearch
  extend ActiveSupport::Concern

  SEARCH_LIMIT = 30
  SEARCH_VISIT_CAP = 5000 # ponytail: bounded walk, index if KBs outgrow this

  private

  def search_entries(query)
    found = []
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
          queue << rel if is_dir && !Kb::Project.at(base, rel)&.locked? # locked projects stay behind the lock
          next unless rel.downcase.include?(query) || (!query.empty? && !is_dir && Kb::Note.read(abs).downcase.include?(query))

          type = is_dir ? (Kb::Project.at(base, rel) ? "project" : "dir") : "file"
          next if query.empty? && type != "project"

          found << { src: index, path: rel, name: name, type: type, source: source[:label],
                     rank: [ { "project" => 0, "dir" => 1, "file" => 2 }[type], name.downcase.include?(query) ? 0 : 1 ] }
        end
      end
    end
    found.sort_by { |e| e[:rank] }.first(SEARCH_LIMIT).each { |e| e.delete(:rank) }
  end

  def children(dir)
    Dir.children(dir).sort
  rescue SystemCallError
    []
  end
end
