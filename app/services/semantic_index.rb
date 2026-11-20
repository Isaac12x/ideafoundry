# Registry of everything the semantic sidecar indexes besides KB files (those are SemanticIndexJob's delta walk).
# Per type: model, palette group label, scope(user) (sweeps + access re-check of hits), item(record) -> { title, hint, url, kind } for results.
# Section extraction lives on each model (`semantic_index ...` macro, SemanticIndexable); ids are u<uid>:<type>:<record id>.
#
# Not indexed, by design:
#   versions (history snapshots of ideas already indexed) | activity_logs, agent_events/runs, notifications, export/capture/kb_fs/kb_media_edit jobs (system noise)
#   api_keys, idea_agent_tokens, users, service_settings (secrets/config) | kb_entry_preferences, kb_links, idea_kb_links, idea_dependencies,
#   idea_lists, github_repositories, licensor_imports, kanban_boards, mood_images (pointers/layout/metadata, no user prose)
#   knowledge_extractions (the markdown is mirrored in the attachment's ocr_text: indexed as "attachment"; KB-file extractions land as KB files)
#   voice/typing fingerprints (biometric)
module SemanticIndex
  Type = Struct.new(:type, :model, :label, :scope, :item, :includes)

  BATCH = 32
  SECTION_CHARS = 1200
  MAX_SECTIONS = 400 # per record; a 500-page OCR'd book is capped, the rest still lives in the KB/attachment

  R = Rails.application.routes.url_helpers
  TYPES = {}

  module_function

  # Long text -> sections of paragraphs packed up to SECTION_CHARS, so an edit re-embeds one section, not the whole text.
  def split(text, size: SECTION_CHARS)
    out = [ +"" ]
    text.to_s.split(/\n\s*\n|\r?\n/).map(&:squish).reject(&:empty?).each do |para|
      para.scan(/.{1,#{size}}(?:\s|\z)/m).each do |piece|
        out << +"" if out.last.size + piece.size > size
        out.last << " " unless out.last.empty?
        out.last << piece.strip
      end
    end
    out.reject(&:empty?).first(MAX_SECTIONS)
  end

  def kb_src(user, source_path) = KbSource.list(user).index { |s| s[:path] == source_path }

  def kb_file_url(user, source_path, rel)
    src = kb_src(user, source_path)
    src ? R.kb_path(src: src, file: rel) : R.kb_path
  end

  def own_ideas(user) = user.ideas.where(discarded_at: nil)
  def short(text, n = 80) = text.to_s.squish.truncate(n)

  def define(type, model, label, scope:, item:, includes: [])
    TYPES[type] = Type.new(type, model, label, scope, item, includes)
  end

  def type_for(klass) = TYPES.values.find { |t| t.model == klass.name }&.type
  def [](type) = TYPES[type.to_s]

  # Records of one type that the user may see, by id (hit ids -> rows). Anything missing was deleted or is not theirs: dropped by the caller.
  def records(user, type, ids)
    t = TYPES.fetch(type)
    t.scope.call(user).where(id: ids).then { |rel| t.includes.any? ? rel.preload(*t.includes) : rel }.index_by { |r| r.id.to_s }
  end

  # Parses "u<uid>:<type>:<key>" -> [type, key]; nil for KB ids or other users' ids.
  def parse(user, doc_id)
    m = doc_id.to_s.match(/\Au#{user.id}:([a-z_]+):(\d+)\z/)
    m && TYPES.key?(m[1]) ? [ m[1], m[2] ] : nil
  end

  # Superset of every record doc id the user has (cheap: ids only; sections may still be blank, so prune keep-lists stay safe).
  def all_ids(user)
    TYPES.values.flat_map { |t| t.scope.call(user).pluck(:id).map { |id| SemanticSearch.record_id(user.id, t.type, id) } }
  end

  # Full sweep: enqueue every record of every type, then prune that type's stale ids. false as soon as the sidecar refuses.
  def sweep_records(user)
    TYPES.each_value do |t|
      keep = []
      t.scope.call(user).then { |rel| t.includes.any? ? rel.preload(*t.includes) : rel }.find_in_batches(batch_size: BATCH) do |batch|
        items = batch.map { |r| { id: SemanticSearch.record_id(user.id, t.type, r.id), sections: r.semantic_sections } }
        return false unless SemanticSearch.enqueue(items)

        keep.concat(items.reject { |i| i[:sections].empty? }.map { |i| i[:id] })
      end
      return false unless SemanticSearch.prune(SemanticSearch.record_id(user.id, t.type, ""), keep)
    end
    true
  end

  define "idea", "Idea", "Ideas", includes: [ :rich_text_description, :notes, :topologies, :themes, :todo_items ],
         scope: ->(u) { own_ideas(u) },
         item: ->(r) {
           r.draft? ? { title: r.title.presence || short(r.description.to_plain_text, 80).presence || "Untitled draft", hint: "resume", url: R.edit_idea_path(r, draft: 1), kind: "draft", group: "Drafts" }
                    : { title: Kb::References.idea_label(r), hint: r.state.to_s.tr("_", " "), url: R.idea_path(r), kind: "idea" }
         }
  define "note", "Note", "Notes", includes: [ :idea ],
         scope: ->(u) { Note.where(idea_id: own_ideas(u).select(:id)) },
         item: ->(r) { { title: short(r.body), hint: r.idea.title, url: R.idea_path(r.idea_id), kind: "note" } }
  define "todo", "TodoItem", "To-dos", includes: [ :idea ],
         scope: ->(u) { TodoItem.visible_to(u) },
         item: ->(r) {
           url = r.idea_id ? R.idea_path(r.idea_id, anchor: "todo") : (r.project_path.present? ? R.kb_path(src: r.project_src, project: r.project_path) : R.root_path)
           { title: r.title, hint: r.completed? ? "done" : r.idea&.title || "to-do", url: url, kind: "todo" }
         }
  define "list", "List", "Lists", scope: ->(u) { u.lists },
         item: ->(r) { { title: r.name, hint: r.kind, url: R.list_path(r), kind: "list" } }
  define "list_item", "ListItem", "List items", includes: [ :list ],
         scope: ->(u) { ListItem.where(list_id: u.lists.select(:id)) },
         item: ->(r) { { title: r.title, hint: r.list.name, url: R.list_path(r.list_id), kind: "list_item" } }
  define "topology", "Topology", "Topologies", scope: ->(u) { u.topologies },
         item: ->(r) { { title: r.name, hint: r.topology_type, url: R.topology_path(r), kind: "topology" } }
  define "theme", "Theme", "Themes", scope: ->(u) { u.themes },
         item: ->(r) { { title: r.name, hint: "theme", url: R.settings_themes_path, kind: "theme" } }
  define "problem", "Problem", "Problems", scope: ->(u) { u.problems },
         item: ->(r) { { title: r.title, hint: r.status, url: R.kb_path, kind: "problem" } }
  define "fact", "Fact", "Facts", scope: ->(u) { u.facts },
         item: ->(r) { { title: short(r.body), hint: "fact", url: R.kb_path, kind: "fact" } }
  define "maxim", "Maxim", "Maxims", scope: ->(u) { u.maxims },
         item: ->(r) { { title: short(r.body), hint: "maxim", url: R.kb_path, kind: "maxim" } }
  define "submission", "Submission", "Intake", scope: ->(u) { u.submissions },
         item: ->(r) { { title: r.title, hint: r.status, url: R.submission_path(r), kind: "submission" } }
  define "template", "Template", "Templates", scope: ->(u) { u.templates },
         item: ->(r) { { title: r.name, hint: "template", url: R.template_path(r), kind: "template" } }
  define "agent_thread", "AgentThread", "Agent threads", scope: ->(u) { u.agent_threads },
         item: ->(r) { { title: r.title.presence || "Agent thread", hint: "agent", url: R.settings_local_agent_path, kind: "agent_thread" } }
  define "agent_recommendation", "AgentRecommendation", "Agent recommendations", scope: ->(u) { u.agent_recommendations },
         item: ->(r) { { title: short(r.reasoning.presence || r.action), hint: r.status, url: R.settings_local_agent_path, kind: "agent_recommendation" } }
  define "kb_annotation", "KbAnnotation", "Highlights", includes: [ :user ], scope: ->(u) { u.kb_annotations },
         item: ->(r) { { title: short(r.quote), hint: File.basename(r.relative_path), url: kb_file_url(r.user, r.source_path, r.relative_path), kind: "kb_annotation" } }
  define "kb_bookmark", "KbBookmark", "Bookmarks", includes: [ :user ], scope: ->(u) { u.kb_bookmarks },
         item: ->(r) { { title: r.label, hint: File.basename(r.relative_path), url: kb_file_url(r.user, r.source_path, r.relative_path), kind: "kb_bookmark" } }
  define "licensor", "Licensor", "Licensors", scope: ->(u) { Licensor.where(idea_id: own_ideas(u).select(:id)) },
         item: ->(r) { { title: r.company, hint: r.stage_label, url: R.licensor_path(r), kind: "licensor" } }
  define "licensor_contact", "LicensorContact", "Licensor contacts", includes: [ :licensor ],
         scope: ->(u) { LicensorContact.where(licensor_id: Licensor.where(idea_id: own_ideas(u).select(:id)).select(:id)) },
         item: ->(r) { { title: short(r.summary), hint: r.licensor.company, url: R.licensor_path(r.licensor_id), kind: "licensor_contact" } }
  define "media_digest", "MediaDigest", "Media digests", includes: [ :kb_download ], scope: ->(u) { u.media_digests.current },
         item: ->(r) { { title: r.kb_download.title.presence || r.kb_download.label, hint: "digest", url: kb_download_url(r.kb_download), kind: "media_digest" } }
  define "drawing", "Drawing", "Drawings", includes: [ :idea ], scope: ->(u) { Drawing.where(idea_id: own_ideas(u).select(:id)) },
         item: ->(r) { { title: r.title, hint: r.idea.title, url: R.idea_drawing_path(r.idea_id, r), kind: "drawing" } }
  define "idea_entry", "IdeaEntry", "Tools & competitors", includes: [ :idea ], scope: ->(u) { IdeaEntry.where(idea_id: own_ideas(u).select(:id)) },
         item: ->(r) { { title: r.name, hint: "#{IdeaEntry.singular_for(r.kind)} · #{r.idea.title}", url: R.idea_path(r.idea_id), kind: "idea_entry" } }
  define "attachment", "ActiveStorage::Attachment", "Attachment text",
         scope: ->(u) { ActiveStorage::Attachment.where(record_type: "Idea", record_id: u.ideas.select(:id)).where.not(ocr_text: [ nil, "" ]) },
         item: ->(r) { { title: r.filename.to_s, hint: "OCR text · #{r.record.title}", url: R.idea_path(r.record_id), kind: "attachment" } }
  define "kb_download", "KbDownload", "Downloads", scope: ->(u) { u.kb_downloads },
         item: ->(r) { { title: r.title.presence || r.label, hint: "download", url: kb_download_url(r), kind: "kb_download" } }
  define "build_item", "BuildItem", "Backlog", scope: ->(u) { u.build_items },
         item: ->(r) { { title: r.title, hint: r.completed? ? "done" : "backlog", url: R.build_items_path, kind: "build_item" } }

  def kb_download_url(d) = d.file_rel && d.source_index ? R.kb_path(src: d.source_index, file: d.file_rel) : R.kb_path
  def item(type, record) = TYPES.fetch(type).item.call(record)
  def label(type) = TYPES.fetch(type).label
end
