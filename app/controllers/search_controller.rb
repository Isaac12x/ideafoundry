# Command palette search: grouped hits across ideas, notes, lists, topologies and the KB.
class SearchController < ApplicationController
  include KbEntrySearch

  PER_GROUP = 6

  def index
    q = params[:q].to_s.strip
    return render json: { groups: [] } if q.blank?

    like = "%#{ActiveRecord::Base.sanitize_sql_like(q.downcase)}%"
    ideas = @user.ideas.non_draft.where(discarded_at: nil)
                 .where("LOWER(ideas.title) LIKE :q OR LOWER(ideas.tldr) LIKE :q", q: like)
                 .order(updated_at: :desc).limit(PER_GROUP)
    notes = Note.joins(:idea).merge(@user.ideas.where(discarded_at: nil))
                .where("LOWER(notes.body) LIKE ?", like).order(created_at: :desc).limit(PER_GROUP)
    lists = @user.lists.where("LOWER(lists.name) LIKE ?", like).limit(PER_GROUP)
    topologies = @user.topologies.where("LOWER(topologies.name) LIKE ?", like).limit(PER_GROUP)
    kb = search_entries(q.downcase).first(PER_GROUP)

    groups = [
      [ "Ideas", ideas.map { |i| { title: i.title, hint: i.state.to_s.tr("_", " "), url: idea_path(i) } } ],
      [ "Notes", notes.map { |n| { title: n.body.to_s.squish.truncate(80), hint: n.idea.title, url: idea_path(n.idea_id) } } ],
      [ "Lists", lists.map { |l| { title: l.name, url: list_path(l) } } ],
      [ "Topologies", topologies.map { |t| { title: t.name, url: topology_path(t) } } ],
      [ "Knowledge Base", kb.map { |e| { title: e[:name], hint: e[:type], url: kb_path(src: e[:src], file: e[:path]) } } ]
    ]
    render json: { groups: groups.reject { |_, items| items.empty? }.map { |label, items| { label: label, items: items } } }
  end
end
