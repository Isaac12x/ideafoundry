module IdeaKbLinksHelper
  # Linked entries for the idea page: projects first, then folders, then files.
  # Entries whose source/path vanished come back with missing: true.
  def idea_kb_link_entries(idea, user)
    sources = KbSource.list(user).map { |s| File.expand_path(s[:path]) }
    order = { "project" => 0, "dir" => 1, "file" => 2 }
    idea.kb_links.sort_by { |l| [ order[l.entry_type] || 3, l.position.to_i, l.id ] }.map do |link|
      index = sources.index(link.source_path)
      base = index && sources[index]
      abs = base && File.join(base, link.relative_path)
      exists = abs && !File.symlink?(abs) && File.exist?(abs)
      project = (Kb::Project.at(base, link.relative_path) if exists && link.entry_type == "project")
      # A file/folder inside a locked project is encrypted, not gone.
      locked = (Kb::Project.containing(base, link.relative_path) if base && !exists)
      locked = nil unless locked&.locked?
      { link: link, index: index, missing: !exists && !locked, project: project, locked: locked,
        name: File.basename(link.relative_path), dir: link.relative_path.include?("/") ? File.dirname(link.relative_path) : nil }
    end
  end

  # Recent findings (project + its tests) of each linked, unlocked project: [[entry, [finding, ...]], ...]
  def idea_linked_findings(entries, limit: 5)
    entries.filter_map do |entry|
      project = entry[:project]
      next if project.nil? || project.locked?

      items = idea_project_findings(project).sort_by { |f| f["at"].to_s }.last(limit).reverse
      [ entry, items ] if items.any?
    end
  end

  # Project#all_findings flattened: [{"id","text","at","from"}] (from = test name, nil for the project's own).
  def idea_project_findings(project)
    project.all_findings.flat_map do |group|
      from = group[:owner].equal?(project) ? nil : group[:owner].name
      group[:items].map { |f| f.merge("from" => from) }
    end
  end

  def idea_kb_link_href(entry)
    link = entry[:link]
    return kb_path(src: entry[:index], project: entry[:locked].rel) if entry[:locked]
    return kb_path(src: entry[:index], file: link.relative_path) if link.entry_type == "file"

    return kb_path(src: entry[:index], project: link.relative_path) if link.entry_type == "project"

    kb_path(src: entry[:index], folder: link.relative_path)
  end
end
