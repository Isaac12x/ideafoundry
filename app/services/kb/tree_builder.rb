module Kb
  class TreeBuilder
    CACHE_GENERATION_KEY = "kb/tree/generation"
    SORT_MODES = %w[name_asc name_desc type_asc type_desc date_asc date_desc].freeze
    DEFAULT_SORT = "name_asc".freeze

    class << self
      def build(user)
        new(user).call
      end

      def bust_cache!(user)
        key = cache_generation_key(user.id)
        # increment is atomic; it returns nil when the key is missing (or the store can't), so seed it then.
        Rails.cache.increment(key) || Rails.cache.write(key, cache_generation(user.id) + 1)
      end

      def cache_generation(user_id)
        Rails.cache.read(cache_generation_key(user_id)) || 0
      end

      def cache_generation_key(user_id)
        "#{CACHE_GENERATION_KEY}/#{user_id}"
      end

      def sort_mode_for(user)
        mode = user.settings&.dig("kb", "sort")
        SORT_MODES.include?(mode) ? mode : DEFAULT_SORT
      end

      # Reorders every sibling group in place: download/job placeholders first,
      # then favourites, then the rest, each ordered by mode ("name_asc", ...).
      def sort_tree(tree, mode = DEFAULT_SORT)
        mode = DEFAULT_SORT unless SORT_MODES.include?(mode)
        field, direction = mode.split("_")
        groups = tree.partition { |_, node| %i[download job].include?(node[:type]) }
        placeholders, entries = groups
        favorites, others = entries.partition { |_, node| node[:preference]&.favorite? }
        ordered = [ favorites, others ].flat_map do |group|
          sorted = group.sort_by { |name, node| sort_key(field, name, node) }
          direction == "desc" ? sorted.reverse : sorted
        end
        sorted_pairs = placeholders + ordered
        tree.replace(sorted_pairs.to_h)
        tree.each_value { |node| sort_tree(node[:children], mode) if node[:type] == :dir }
        tree
      end

      private

      def sort_key(field, name, node)
        natural = name.downcase.scan(/\d+|\D+/).map { |part| part.match?(/\A\d/) ? [ 0, part.to_i ] : [ 1, part ] }
        case field
        when "type"
          [ node[:type] == :dir ? 0 : 1, node[:type] == :dir ? "" : File.extname(name).downcase, natural, name ]
        when "date"
          [ node[:mtime].to_f, natural, name ]
        else
          [ natural, name ]
        end
      end
    end

    def initialize(user)
      @user = user
    end

    def call
      sources = KbSource.list(user)
      preferences = user.kb_entry_preferences.with_attached_icon_image.to_a
      preferences_by_key = preferences.index_by do |preference|
        [ preference.source_path, preference.relative_path, preference.entry_type ]
      end
      default_folder_preference = preferences.find(&:default_folder?)
      downloads_by_source = active_downloads_by_source(sources)
      jobs_by_source = user.kb_fs_jobs.visible_in_tree.recent.group_by(&:source_path)
      unseen = unseen_download_keys

      sources.each_with_index.map do |source, index|
        source_path = File.expand_path(source[:path])
        entries = cached_filesystem_entries(source_path)
        tree = build_nested_tree(
          entries[:files],
          entries[:dirs],
          source_path,
          preferences_by_key
        )
        annotate_projects(tree, source_path)
        mark_unseen(tree, source_path, unseen)
        inject_downloads(tree, downloads_by_source[source_path] || [])
        inject_jobs(tree, jobs_by_source[source_path] || [])
        self.class.sort_tree(tree, sort_mode)

        {
          index: index,
          path: source[:path],
          source_path: source_path,
          label: source[:label] || KbSource.label_for(source[:path]),
          files: entries[:files],
          tree: tree,
          exists: Dir.exist?(source_path),
          native: source[:native],
          drive: source[:drive],
          preference: preferences_by_key[[ source_path, "", "root" ]],
          default_folder_preference: default_folder_preference
        }
      end
    end

    private

    attr_reader :user

    def sort_mode
      self.class.sort_mode_for(user)
    end

    def cached_filesystem_entries(base)
      generation = self.class.cache_generation(user.id)
      Rails.cache.fetch([ "kb/tree/fs-v2", user.id, base, generation ]) do
        scan_filesystem_entries(base)
      end
    end

    def scan_filesystem_entries(base)
      files = []
      dirs = []
      return { files: files, dirs: dirs } unless Dir.exist?(base)

      Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH).sort.each do |path|
        next if File.symlink?(path)

        rel = path.delete_prefix("#{base}/")
        next if hidden_path?(rel)

        if File.directory?(path)
          dirs << { rel: rel, mtime: File.mtime(path).to_f }
        elsif File.file?(path)
          files << { rel: rel, abs: path, mtime: File.mtime(path).to_f }
        end
      end
      { files: files, dirs: dirs }
    end

    def hidden_path?(relative_path)
      relative_path.split(File::SEPARATOR).any? { |segment| segment.start_with?(".") }
    end

    def build_nested_tree(files, dirs, source_path, preferences)
      root = {}
      dirs.each do |dir|
        dir_node_for(root, dir[:rel].split("/"), source_path, preferences)[:mtime] = dir[:mtime]
      end
      files.each do |file|
        parts = file[:rel].split("/")
        current = if parts.size > 1
          dir_node_for(root, parts[0..-2], source_path, preferences)[:children]
        else
          root
        end
        current[parts.last] = {
          type: :file,
          rel: file[:rel],
          abs: file[:abs],
          mtime: file[:mtime],
          preference: preferences[[ source_path, file[:rel], "file" ]]
        }
      end
      root
    end

    def dir_node_for(root, parts, source_path, preferences)
      current = root
      node = nil
      parts.each_with_index do |directory, index|
        relative_path = parts[0..index].join("/")
        current[directory] ||= {
          type: :dir,
          children: {},
          rel: relative_path,
          preference: preferences[[ source_path, relative_path, "folder" ]]
        }
        node = current[directory]
        current = node[:children]
      end
      node
    end

    # Marks project dirs (node[:project]) and everything inside a private
    # project (node[:private]) so the UI can hide AI actions.
    def annotate_projects(children, base, inherited_private = false)
      children.each_value do |node|
        next unless node[:type] == :file || node[:type] == :dir

        project = node[:type] == :dir ? Kb::Project.at(base, node[:rel]) : nil
        if project
          node[:project] = { id: project.id, status: project.status, private: project.private?,
                             stage: project.stage, stage_index: project.stages.index(project.stage) || 0,
                             stage_count: project.stages.size, roles: material_roles(project, node[:children]) }
        end
        private_here = inherited_private || project&.private? || false
        node[:private] = true if private_here
        annotate_projects(node[:children], base, private_here) if node[:type] == :dir
      end
    end

    # { child_name => role or nil } for the project's direct children.
    def material_roles(project, children)
      children.keys.to_h { |name| [ name, project.material(name)["role"] ] }
    end

    # Set of [source_path, file_rel] for finished downloads not opened yet.
    def unseen_download_keys
      user.kb_downloads.where(status: "done", opened_at: nil).where.not(filename: [ nil, "" ])
          .pluck(:source_path, :dir, :filename)
          .to_set { |path, dir, name| [ path && File.expand_path(path), dir.present? ? File.join(dir, name) : name ] }
    end

    # Flags unseen file nodes (node[:new]) and their ancestor dirs (node[:has_new]).
    def mark_unseen(children, source_path, unseen)
      return false if unseen.empty?

      children.values.count do |node|
        case node[:type]
        when :file then node[:new] = true if unseen.include?([ source_path, node[:rel] ])
        when :dir then node[:has_new] = true if mark_unseen(node[:children], source_path, unseen)
        end
      end.positive?
    end

    def inject_downloads(tree, downloads)
      downloads.each do |download|
        children = children_for(tree, download.dir)
        next unless children

        children["~download-#{download.id}"] = { type: :download, download: download }
      end
    end

    def inject_jobs(tree, jobs)
      jobs.each do |job|
        children = children_for(tree, job.target_dir)
        children ||= tree if job.failed?
        next unless children

        children["~job-#{job.id}"] = { type: :job, job: job }
      end
    end

    def children_for(tree, relative_dir)
      return tree if relative_dir.blank?

      current = tree
      relative_dir.split("/").each do |segment|
        node = current[segment]
        return nil unless node&.dig(:type) == :dir

        current = node[:children]
      end
      current
    end

    def active_downloads_by_source(sources)
      expanded_sources = sources.map { |source| File.expand_path(source[:path]) }
      user.kb_downloads.in_tree.recent.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |download, grouped|
        path = download.source_path.presence
        path ||= expanded_sources[download.source_index]
        next if path.blank?

        grouped[File.expand_path(path)] << download
      end
    end
  end
end
