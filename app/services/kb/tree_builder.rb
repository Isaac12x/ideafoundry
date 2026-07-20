module Kb
  class TreeBuilder
    def initialize(user)
      @user = user
    end

    def call
      sources = KbSource.list(user)
      preferences = user.kb_entry_preferences.with_attached_icon_image.to_a
      preferences_by_key = preferences.index_by do |preference|
        [preference.source_path, preference.relative_path, preference.entry_type]
      end
      default_folder_preference = preferences.find(&:default_folder?)
      downloads_by_source = active_downloads_by_source(sources)
      jobs_by_source = user.kb_fs_jobs.visible_in_tree.recent.group_by(&:source_path)

      sources.each_with_index.map do |source, index|
        source_path = File.expand_path(source[:path])
        entries = filesystem_entries(source_path)
        tree = build_nested_tree(
          entries[:files],
          entries[:dirs],
          source_path,
          preferences_by_key
        )
        inject_downloads(tree, downloads_by_source[source_path] || [])
        inject_jobs(tree, jobs_by_source[source_path] || [])

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
          preference: preferences_by_key[[source_path, "", "root"]],
          default_folder_preference: default_folder_preference
        }
      end
    end

    private

    attr_reader :user

    def filesystem_entries(base)
      files = []
      dirs = []
      return { files: files, dirs: dirs } unless Dir.exist?(base)

      Dir.glob(File.join(base, "**", "*"), File::FNM_DOTMATCH).sort.each do |path|
        next if File.symlink?(path)

        rel = path.delete_prefix("#{base}/")
        next if hidden_path?(rel)

        if File.directory?(path)
          dirs << rel
        elsif File.file?(path)
          files << { rel: rel, abs: path }
        end
      end
      { files: files, dirs: dirs }
    end

    def hidden_path?(relative_path)
      relative_path.split(File::SEPARATOR).any? { |segment| segment.start_with?(".") }
    end

    def build_nested_tree(files, dirs, source_path, preferences)
      root = {}
      dirs.each do |relative_path|
        dir_node_for(root, relative_path.split("/"), source_path, preferences)
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
          preference: preferences[[source_path, file[:rel], "file"]]
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
          preference: preferences[[source_path, relative_path, "folder"]]
        }
        node = current[directory]
        current = node[:children]
      end
      node
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
      user.kb_downloads.active.recent.each_with_object(Hash.new { |hash, key| hash[key] = [] }) do |download, grouped|
        path = download.source_path.presence
        path ||= expanded_sources[download.source_index]
        next if path.blank?

        grouped[File.expand_path(path)] << download
      end
    end
  end
end
