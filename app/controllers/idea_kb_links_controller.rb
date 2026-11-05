# Links an idea to KB projects, folders and files. Created from the idea page.
class IdeaKbLinksController < ApplicationController
  before_action :set_user
  before_action :set_idea, except: :search # search is idea-independent (also used by the new-idea form)

  SEARCH_LIMIT = 30
  SEARCH_VISIT_CAP = 5000 # ponytail: bounded walk, index if KBs outgrow this

  def search
    # Blank query lists projects only, so the picker shows them on focus.
    query = params[:q].to_s.strip.downcase
    render json: { results: search_entries(query) }
  end

  def create
    source = KbSource.list(@user)[params[:src].to_i] unless params[:src].to_i.negative?
    entry = source && IdeaKbLink.resolve_entry(File.expand_path(source[:path]), params[:path])
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
          next if File.symlink?(abs) || Kb::Note.sidecar?(name) # the note rides on its file's row

          is_dir = File.directory?(abs)
          queue << rel if is_dir
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

  def set_user
    @user = User.first
  end

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end
end
