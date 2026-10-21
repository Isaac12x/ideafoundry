# "Also in" aliases and related links between KB entries (see KbLink).
# The canonical file stays where it is; these rows only point at it.
class KbLinksController < ApplicationController
  before_action :set_user

  def create_alias
    canonical = entry(params[:src], params[:path])
    dest = entry(params[:dest_src], params[:dest_dir], dir: true)
    return fail_with("Only files can be placed in another folder.") unless canonical && canonical[:type] == "file" && dest

    slot = [ dest[:rel], File.basename(canonical[:rel]) ].reject(&:blank?).join("/")
    if File.exist?(File.join(dest[:base], slot)) || KbLink.aliases_in(@user, dest[:base]).exists?(peer_relative_path: slot)
      return fail_with("\"#{File.basename(slot)}\" already exists in that folder.")
    end

    @user.kb_links.create!(kind: "alias", source_path: canonical[:base], relative_path: canonical[:rel],
                           peer_source_path: dest[:base], peer_relative_path: slot)
    respond_tree
  end

  def destroy_alias
    @user.kb_links.aliases.find(params[:id]).destroy
    respond_tree
  end

  def create_related
    a = entry(params[:src], params[:path])
    b = entry(params[:peer_src], params[:peer_path])
    return fail_with("Entry not found.") unless a && b

    link = @user.kb_links.new(kind: "related", source_path: a[:base], relative_path: a[:rel],
                              peer_source_path: b[:base], peer_relative_path: b[:rel])
    return fail_with(link.errors.full_messages.to_sentence) unless link.save

    respond_related(a)
  end

  def destroy_related
    link = @user.kb_links.related.find(params[:id])
    link.destroy
    respond_related({ base: link.source_path, rel: link.relative_path })
  end

  private

  # { base:, rel:, type: } for an existing entry (or the source root when dir && blank).
  def entry(src, rel, dir: false)
    source = KbSource.list(@user)[src.to_i] if src.to_s.match?(/\A\d+\z/)
    return unless source

    base = File.expand_path(source[:path])
    return { base: base, rel: "", type: "dir" } if dir && rel.blank? && Dir.exist?(base)

    found = IdeaKbLink.resolve_entry(base, rel)
    return if found.nil? || (dir && found[:type] == "file")

    found.merge(base: base)
  end

  def fail_with(message)
    return render(json: { error: message }, status: :unprocessable_content) if request.format.json?

    redirect_to kb_path, alert: message
  end

  def respond_tree
    Kb::TreeBuilder.bust_cache!(@user)
    return redirect_to(kb_path) unless request.format.turbo_stream?

    render turbo_stream: turbo_stream.replace(
      "kb-sidebar-tree", partial: "kb/tree",
      locals: { folders: Kb::TreeBuilder.build(@user), selected_file: params[:sel_file].presence,
                selected_folder_index: params[:sel_src].presence&.to_i }
    )
  end

  def respond_related(entry)
    return redirect_to(kb_path) unless request.format.turbo_stream?

    index = KbSource.list(@user).index { |s| File.expand_path(s[:path]) == entry[:base] }
    render turbo_stream: turbo_stream.replace("kb-related", partial: "kb/related", locals: { src: index, rel: entry[:rel] })
  end
end
