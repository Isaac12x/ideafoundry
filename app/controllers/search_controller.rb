# Command palette search: grouped hits across ideas, notes, lists, topologies and the KB.
class SearchController < ApplicationController
  include KbEntrySearch

  PER_GROUP = 6

  def index
    q = params[:q].to_s.strip
    return render json: { groups: [] } if q.blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(q.downcase)}%"
    # ponytail: LIKE on raw ActionText HTML also matches tag/attribute text (e.g. "div"); strip-aware FTS if it bites
    match = <<~SQL.squish
      LOWER(ideas.title) LIKE :q OR LOWER(ideas.tldr) LIKE :q OR EXISTS (
        SELECT 1 FROM action_text_rich_texts art
        WHERE art.record_type = 'Idea' AND art.record_id = ideas.id AND art.name = 'description' AND LOWER(art.body) LIKE :q)
    SQL
    ideas = @user.ideas.non_draft.where(discarded_at: nil)
                 .where(match, q: like)
                 .order(updated_at: :desc).limit(PER_GROUP)
    drafts = @user.ideas.drafts.where(discarded_at: nil)
                 .includes(:rich_text_description)
                 .where(match, q: like)
                 .order(updated_at: :desc).limit(PER_GROUP)
    notes = Note.joins(:idea).merge(@user.ideas.where(discarded_at: nil))
                .where("LOWER(notes.body) LIKE ?", like).order(created_at: :desc).limit(PER_GROUP)
    lists = @user.lists.where("LOWER(lists.name) LIKE ?", like).limit(PER_GROUP)
    topologies = @user.topologies.where("LOWER(topologies.name) LIKE ?", like).limit(PER_GROUP)
    kb = search_entries(q.downcase).first(PER_GROUP)

    groups = [
      [ "Ideas", ideas.map { |i| { title: i.title, hint: i.state.to_s.tr("_", " "), url: idea_path(i) } } ],
      [ "Drafts", drafts.map { |i| { title: draft_title(i), hint: "resume", url: edit_idea_path(i, draft: 1) } } ],
      [ "Notes", notes.map { |n| { title: n.body.to_s.squish.truncate(80), hint: n.idea.title, url: idea_path(n.idea_id) } } ],
      [ "Lists", lists.map { |l| { title: l.name, url: list_path(l) } } ],
      [ "Topologies", topologies.map { |t| { title: t.name, url: topology_path(t) } } ],
      [ "Knowledge Base", kb.map { |e| { title: e[:name], hint: e[:type], url: kb_path(src: e[:src], file: e[:path]) } } ]
    ]
    render json: { groups: groups.reject { |_, items| items.empty? }.map { |label, items| { label: label, items: items } } }
  end

  private

  def draft_title(idea)
    idea.title.presence || idea.description.to_plain_text.lines.map(&:squish).find(&:present?)&.truncate(80) || "Untitled draft"
  end
end
