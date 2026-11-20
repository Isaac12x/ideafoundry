# Command palette search: grouped hits across ideas, notes, lists, topologies and the KB.
# mode=quick (title/substring), similar (semantic via the SemanticSearch sidecar when up, else TF-IDF; vs a seed idea/KB entry or the typed text), deep (all words in full text, with snippets).
class SearchController < ApplicationController
  include KbEntrySearch

  PER_GROUP = 6
  DEEP_PER_GROUP = 8
  DEEP_BUDGET = 1.5 # seconds; ponytail: bounded scan of the KB, FTS5 index if this gets cut off
  CORPUS = 500

  def index
    q = params[:q].to_s.strip
    mode = %w[similar deep].include?(params[:mode]) ? params[:mode] : "quick"
    groups, terms = case mode
    when "similar" then [ similar_groups(q), [] ]
    when "deep" then deep_groups(q)
    else [ q.blank? ? [] : quick_groups(q), [] ]
    end
    render json: { groups: groups.reject { |_, items| items.empty? }.map { |label, items| { label: label, items: items } }, terms: terms }
  end

  private

  def quick_groups(q)
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

    [
      [ "Ideas", ideas.map { |i| idea_item(i, hint: i.state.to_s.tr("_", " ")) } ],
      [ "Drafts", drafts.map { |i| { title: draft_title(i), hint: "resume", url: edit_idea_path(i, draft: 1), kind: "draft", actions: basic_actions(edit_idea_path(i, draft: 1), "Resume") } } ],
      [ "Notes", notes.map { |n| { title: n.body.to_s.squish.truncate(80), hint: n.idea.title, url: idea_path(n.idea_id), kind: "note", actions: basic_actions(idea_path(n.idea_id)) } } ],
      [ "Lists", lists.map { |l| { title: l.name, url: list_path(l), kind: "list", actions: basic_actions(list_path(l)) } } ],
      [ "Topologies", topologies.map { |t| { title: t.name, url: topology_path(t), kind: "topology", actions: basic_actions(topology_path(t)) } } ],
      [ "Knowledge Base", kb.map { |e| kb_item(e) } ]
    ]
  end

  # --- Similar ---

  def similar_groups(q)
    semantic_similar_groups(q) || tfidf_similar_groups(q)
  end

  # nil = sidecar off/down/seed not indexed yet -> caller falls back to TF-IDF.
  def semantic_similar_groups(q)
    return unless SemanticSearch.enabled?

    seed = if params[:idea].present? then { id: SemanticSearch.idea_id(@user.id, params[:idea].to_i) }
    elsif params[:path].present? then { id: SemanticSearch.kb_id(@user.id, params[:src].to_i, params[:path].to_s) }
    elsif q.present? then { query: q }
    end
    return unless seed

    hits = SemanticSearch.search(prefix: SemanticSearch.prefix(@user.id), k: 12, exclude: [ seed[:id] ].compact, **seed)
    return if hits.blank?

    ideas = @user.ideas.non_draft.where(discarded_at: nil).where(id: hits.filter_map { |h| h["id"][/\Au\d+:idea:(\d+)\z/, 1] }).index_by { |i| i.id.to_s }
    entries = kb_entry_index.index_by { |e| SemanticSearch.kb_id(@user.id, e[:src], e[:path]) }
    pct = ->(h) { "#{(h['score'].to_f * 100).round}% match" }
    idea_hits = hits.filter_map { |h| (i = ideas[h["id"][/:idea:(\d+)\z/, 1]]) && idea_item(i, hint: pct.(h)) }
    kb_hits = hits.filter_map { |h| (e = entries[h["id"]]) && kb_item(e.slice(:src, :path, :name, :type, :source), hint: pct.(h)) }
    [ [ "Ideas", idea_hits.first(PER_GROUP) ], [ "Knowledge Base", kb_hits.first(PER_GROUP) ] ]
  end

  def tfidf_similar_groups(q)
    seed_text, skip_idea, skip_kb = similar_seed(q)
    return [] if seed_text.blank?

    docs = idea_corpus.reject { |i| i.id == skip_idea }.map { |i| { idea: i, text: idea_text(i) } }
    docs += kb_entry_index.reject { |e| [ e[:src], e[:path] ] == skip_kb }.map { |e| { entry: e, text: "#{e[:rel_down]} #{e[:note_down]}" } }
    ranked = PaletteSearch.similar(seed_text, docs, limit: 12)
    pct = ->(d) { "#{(d[:score] * 100).round}% match" }
    [
      [ "Ideas", ranked.select { |d| d[:idea] }.first(PER_GROUP).map { |d| idea_item(d[:idea], hint: pct.(d)) } ],
      [ "Knowledge Base", ranked.select { |d| d[:entry] }.first(PER_GROUP).map { |d| kb_item(d[:entry].slice(:src, :path, :name, :type, :source), hint: pct.(d)) } ]
    ]
  end

  # [seed text, idea id to leave out, [src, path] to leave out]
  def similar_seed(q)
    if params[:idea].present?
      idea = @user.ideas.find_by(id: params[:idea])
      [ idea && idea_text(idea), idea&.id, nil ]
    elsif params[:path].present?
      src = params[:src].to_i
      [ kb_seed_text(src, params[:path].to_s), nil, [ src, params[:path].to_s ] ]
    else
      [ q, nil, nil ]
    end
  end

  def kb_seed_text(src, rel)
    entry = kb_entry_index.find { |e| e[:src] == src && e[:path] == rel }
    return unless entry

    "#{entry[:rel_down].tr('/', ' ')} #{entry[:note_down]} #{kb_file_text(entry, 8.kilobytes)}"
  end

  # --- Deep ---

  def deep_groups(q)
    words = q.downcase.split.uniq.select { |w| w.length >= 2 }
    return [ [], [] ] if words.empty?

    ideas = idea_corpus.filter_map do |i|
      text = idea_text(i)
      score = PaletteSearch.deep_score(text, words)
      [ score, i, text ] if score.positive?
    end.sort_by { |score, i, _| [ -score, -i.updated_at.to_i ] }.first(DEEP_PER_GROUP)

    [
      [ [ "Ideas", ideas.map { |_, i, text| idea_item(i, hint: "match", snippet: PaletteSearch.snippet(text, words)) } ],
        [ "Knowledge Base", deep_kb(words) ] ],
      words
    ]
  end

  def deep_kb(words)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + DEEP_BUDGET
    hits = []
    kb_entry_index.each do |e|
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline

      text = "#{e[:name]} #{e[:note_down]} #{kb_file_text(e, DEEP_FILE_BYTES)}"
      score = PaletteSearch.deep_score(text, words)
      hits << [ score, e, text ] if score.positive?
    end
    hits.sort_by { |score, _, _| -score }.first(DEEP_PER_GROUP).map do |_, e, text|
      kb_item(e.slice(:src, :path, :name, :type, :source), hint: "match", snippet: PaletteSearch.snippet(text, words))
    end
  end

  def idea_corpus
    @user.ideas.non_draft.where(discarded_at: nil).includes(:rich_text_description, :notes, :topologies, :themes)
         .order(updated_at: :desc).limit(CORPUS)
  end

  def idea_text(idea) = idea.search_text

  # --- Items + drill-in actions. run: go (visit) | tab | copy | post (JSON, then refresh) | similar (client re-queries) ---

  def basic_actions(url, open_label = "Open")
    [ { label: open_label, run: "go", url: url }, { label: "Open in new tab", run: "tab", url: url }, { label: "Copy link", run: "copy", value: url } ]
  end

  def idea_item(idea, hint: nil, snippet: nil)
    url = idea_path(idea)
    actions = basic_actions(url) + [
      { label: "Edit", run: "go", url: edit_idea_path(idea) },
      { label: "Add to-do", run: "go", url: idea_path(idea, anchor: "todo") },
      { label: "Find similar", run: "similar", idea: idea.id }
    ]
    @user.lists.named.limit(5).each { |l| actions << { label: "Add to list: #{l.name}", run: "post", url: add_to_list_idea_path(idea), params: { list_id: l.id } } }
    actions << { label: idea.for_licensing? ? "Stop tracking for licensing" : "Track for licensing", run: "post", url: toggle_licensing_idea_path(idea) } if feature_enabled?(:licensing)
    actions << { label: "Archive", run: "post", url: archive_idea_path(idea) }
    { title: Kb::References.idea_label(idea), hint: hint, snippet: snippet, url: url, kind: "idea", id: idea.id, actions: actions }.compact
  end

  def kb_item(e, hint: nil, snippet: nil)
    url = kb_entry_url(e)
    dir = File.dirname(e[:path])
    actions = [
      { label: "Open", run: "go", url: url },
      { label: "Reveal in tree", run: "go", url: kb_path(src: e[:src], folder: e[:type] == "file" ? (dir == "." ? nil : dir) : e[:path]) },
      { label: "Copy path", run: "copy", value: e[:path] },
      { label: "Copy link", run: "copy", value: url },
      { label: "Open in Finder", run: "post", url: kb_fs_open_path, params: { src: e[:src], path: e[:path] }, refresh: false },
      { label: "Find similar", run: "similar", src: e[:src], path: e[:path] }
    ]
    actions.insert(2, { label: "New test or lock (project page)", run: "go", url: url }) if e[:type] == "project"
    { title: e[:name], hint: hint || e[:type], snippet: snippet, url: url, kind: e[:type], actions: actions }.compact
  end

  def draft_title(idea)
    idea.title.presence || idea.description.to_plain_text.lines.map(&:squish).find(&:present?)&.truncate(80) || "Untitled draft"
  end
end
