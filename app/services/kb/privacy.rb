module Kb
  # Single choke point: is a KB path (file or dir) inside, or itself, a private project?
  # Cost per call: one stat per ancestor + one YAML read per project marker found.
  # Pass a shared `memo` Hash across calls (e.g. a tree walk) to make it O(1) per
  # ancestor after the first visit. A memo is only valid for one request/walk.
  module Privacy
    module_function

    def private?(base, rel, memo = nil)
      base = File.expand_path(base)
      parts = rel.to_s.split("/").reject(&:blank?)
      return true if parts.include?("..") # fail closed on traversal

      (0..parts.size).any? { |n| marker_private?(base, parts.first(n).join("/"), memo) }
    end

    # ponytail: no symlink check here; tree/ContextReader already skip symlinks.
    def marker_private?(base, dir_rel, memo)
      key = "#{base}\0#{dir_rel}"
      return memo[key] if memo&.key?(key)

      marker = File.join(base, dir_rel, Project::META_FILE)
      value = File.file?(marker) ? Project.read_meta(marker)["private"] != false : false
      memo[key] = value if memo
      value
    end
  end
end
