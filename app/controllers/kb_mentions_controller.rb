# One "@" search across everything a project text can reference: ideas (each version of an idea is its own row, so
# "Idea name v3" finds that version), KB files/folders/projects, maxims, IPFs/BPFs and problems.
# Results carry the ready-to-insert token (see Kb::References).
class KbMentionsController < ApplicationController
  include KbEntrySearch

  LIMIT = 6
  VERSION_SUFFIX = /\s+v(\d+)\z/i

  def search
    query = params[:q].to_s.strip
    return render json: { results: [] } if query.blank?

    version = query[VERSION_SUFFIX, 1]&.to_i
    like = "%#{ActiveRecord::Base.sanitize_sql_like(query.sub(VERSION_SUFFIX, '').downcase)}%"
    results = idea_results(like, version) + kb_results(query.downcase) + text_results(like)
    render json: { results: results }
  end

  private

  def idea_results(like, version)
    scope = @user.ideas.non_draft.where(discarded_at: nil).where("LOWER(title) LIKE ?", like)
    scope = scope.where(version_number: version) if version
    scope.order(updated_at: :desc).limit(LIMIT).map do |idea|
      ref = Kb::References::Ref.new(label: Kb::References.idea_label(idea), type: "idea", ref: idea.id)
      { kind: "idea", title: ref.label, token: ref.token }
    end
  end

  def kb_results(query)
    search_entries(query).first(LIMIT).map do |e|
      ref = Kb::References::Ref.new(label: e[:name], type: "kb", ref: Kb::References.kb_ref(e[:src], e[:type], e[:path]))
      { kind: e[:type] == "file" ? "file" : "kb", title: e[:name], hint: e[:path], token: ref.token }
    end
  end

  def text_results(like)
    [ [ "maxim", @user.maxims.where("LOWER(body) LIKE ?", like), :body ],
      [ "fact", @user.facts.where("LOWER(body) LIKE ?", like), :body ],
      [ "problem", @user.problems.where("LOWER(title) LIKE ?", like), :title ] ].flat_map do |type, scope, field|
      scope.recent.limit(LIMIT).map do |record|
        label = record.public_send(field).to_s.squish.truncate(70)
        { kind: type, title: label, token: Kb::References::Ref.new(label: label, type: type, ref: record.id).token }
      end
    end
  end
end
