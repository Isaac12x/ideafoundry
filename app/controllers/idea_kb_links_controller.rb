# Links an idea to KB projects, folders and files. Created from the idea page.
class IdeaKbLinksController < ApplicationController
  before_action :set_user
  before_action :set_idea

  SEARCH_LIMIT = 30
  SEARCH_VISIT_CAP = 5000 # ponytail: bounded walk, index if KBs outgrow this

  def search
    query = params[:q].to_s.strip.downcase
    return render json: { results: [] } if query.blank?

    render json: { results: search_entries(query) }
  end

  def create
    source = KbSource.list(@user)[params[:src].to_i] unless params[:src].to_i.negative?
    entry = source && resolve_entry(File.expand_path(source[:path]), params[:path])
    return head(:unprocessable_content) unless entry

    @idea.kb_links.find_or_create_by!(source_path: source[:path], relative_path: entry[:rel]) do |link|
      link.entry_type = entry[:type]
      link.position = @idea.kb_links.maximum(:position).to_i + 1
    end
    respond_section
  end

  def destroy
    @idea.kb_links.find(params[:id]).destroy
    respond_section
  end

  private

  def respond_section
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("idea_kb_links_#{@idea.id}",
                                                  partial: "ideas/kb_links", locals: { idea: @idea.reload })
      end
      format.html { redirect_to idea_path(@idea) }
    end
  end

  # { rel:, type: } for an existing, non-hidden, symlink-free entry inside base.
  def resolve_entry(base, rel)
    rel = IdeaKbLink.normalize_relative_path(rel)
    parts = rel.split("/")
    return if parts.empty? || parts.any? { |p| p.start_with?(".") || p == ".." }

    abs = File.expand_path(File.join(base, rel))
    return unless abs.start_with?("#{base}/")
    return if parts.each_with_index.any? { |_, i| File.symlink?(File.join(base, *parts.first(i + 1))) }
    return unless File.exist?(abs)

    type = Kb::Project.at(base, rel) ? "project" : (File.directory?(abs) ? "dir" : "file")
    { rel: rel, type: type }
  end

  def search_entries(query)
    found = []
    visited = 0
    KbSource.list(@user).each_with_index do |source, index|
      base = File.expand_path(source[:path])
      next unless File.directory?(base)

      queue = [""]
      until queue.empty? || visited > SEARCH_VISIT_CAP
        dir = queue.shift
        children(File.join(base, dir)).each do |name|
          next if name.start_with?(".")

          visited += 1
          rel = dir.empty? ? name : "#{dir}/#{name}"
          abs = File.join(base, rel)
          next if File.symlink?(abs)

          is_dir = File.directory?(abs)
          queue << rel if is_dir
          next unless rel.downcase.include?(query)

          type = is_dir ? (Kb::Project.at(base, rel) ? "project" : "dir") : "file"
          found << { src: index, path: rel, name: name, type: type, source: source[:label],
                     rank: [{ "project" => 0, "dir" => 1, "file" => 2 }[type], name.downcase.include?(query) ? 0 : 1] }
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

  def set_user
    @user = User.first
  end

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end
end
