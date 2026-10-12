module IdeaKbLinksHelper
  # Linked entries for the idea page: projects first, then folders, then files.
  # Entries whose source/path vanished come back with missing: true.
  def idea_kb_link_entries(idea, user)
    sources = KbSource.list(user).map { |s| File.expand_path(s[:path]) }
    order = { "project" => 0, "dir" => 1, "file" => 2 }
    idea.kb_links.sort_by { |l| [order[l.entry_type] || 3, l.position.to_i, l.id] }.map do |link|
      index = sources.index(link.source_path)
      base = index && sources[index]
      abs = base && File.join(base, link.relative_path)
      exists = abs && !File.symlink?(abs) && File.exist?(abs)
      project = (Kb::Project.at(base, link.relative_path) if exists && link.entry_type == "project")
      { link: link, index: index, missing: !exists, project: project,
        name: File.basename(link.relative_path), dir: link.relative_path.include?("/") ? File.dirname(link.relative_path) : nil }
    end
  end

  def idea_kb_link_href(entry)
    link = entry[:link]
    return kb_path(src: entry[:index], file: link.relative_path) if link.entry_type == "file"

    return kb_path(src: entry[:index], project: link.relative_path) if link.entry_type == "project"

    kb_path(src: entry[:index], folder: link.relative_path)
  end
end
