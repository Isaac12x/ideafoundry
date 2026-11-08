# Adds/removes the non-idea entries of a named list: free text/links, or an idea or KB entry picked from the matches.
class ListItemsController < ApplicationController
  before_action :set_user
  before_action :set_list

  def create
    text = params[:text].to_s
    pick = params[:pick].to_s
    return redirect_back(fallback_location: @list, alert: "Type something to add.") if text.blank? && pick.blank?

    if pick.start_with?("idea:")
      @list.idea_lists.find_or_create_by!(idea: @user.ideas.kept.non_draft.find(pick.delete_prefix("idea:")))
      return redirect_back(fallback_location: @list, notice: "Idea added to the list.")
    end

    item = pick.present? ? kb_item(pick.delete_prefix("kb:")) : ListItem.from_text(text)
    return redirect_back(fallback_location: @list, alert: "That knowledge base entry no longer exists.") unless item

    item.list = @list

    if item.save
      redirect_back fallback_location: @list, notice: "Added to the list."
    else
      redirect_back fallback_location: @list, alert: item.errors.full_messages.to_sentence
    end
  end

  def destroy
    @list.list_items.find(params[:id]).destroy!
    redirect_back fallback_location: @list, notice: "Removed from the list."
  end

  private

  def set_list
    @list = @user.lists.named.find(params[:list_id])
  end

  # Validated against disk like IdeaKbLinksController#create; the type comes from the entry, not the client.
  def kb_item(kb)
    src, _type, path = kb.split(":", 3)
    source = KbSource.list(@user)[src.to_i] unless src.to_i.negative?
    entry = source && IdeaKbLink.resolve_entry(File.expand_path(source[:path]), path)
    return unless entry

    param = { "file" => :file, "project" => :project }.fetch(entry[:type], :folder)
    ListItem.new(title: File.basename(entry[:rel]), url: kb_path(src: src.to_i, param => entry[:rel]))
  end
end
