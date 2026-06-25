class Version < ApplicationRecord
  belongs_to :idea
  belongs_to :parent_version, class_name: 'Version', optional: true
  has_many :child_versions, class_name: 'Version', foreign_key: 'parent_version_id', dependent: :destroy

  # Validations
  validates :commit_message, presence: true
  validates :snapshot_data, presence: true

  # Callbacks
  before_validation :generate_snapshot, on: :create, if: -> { snapshot_data.blank? }
  before_create :generate_diff_summary

  # Serialize snapshot_data as JSON
  serialize :snapshot_data, coder: JSON

  # Scopes
  scope :for_idea, ->(idea) { where(idea: idea).order(created_at: :desc) }
  scope :root_versions, -> { where(parent_version_id: nil) }
  scope :chronological, -> { reorder(created_at: :asc) }

  # Create a new version from the current idea state
  def self.create_from_idea(idea, commit_message, parent_version = nil, force: false, replace_message: true, automatic: false)
    snapshot = snapshot_for(idea)
    latest = idea.versions.order(created_at: :desc).first

    if !force && latest && snapshots_equal?(latest.snapshot_data, snapshot) && (automatic || idea.reusable_history_version?(latest))
      latest.update!(
        commit_message: replace_message ? commit_message : latest.commit_message,
        parent_version: parent_version || latest.parent_version,
        diff_summary: diff_summary_for(snapshot, (parent_version || latest.parent_version)&.snapshot_data)
      )
      idea.mark_reusable_history_version!(latest) if automatic
      idea.clear_reusable_history_version! unless automatic
      return latest
    end

    version = create!(
      idea: idea,
      parent_version: parent_version || latest,
      commit_message: commit_message,
      snapshot_data: snapshot
    )
    idea.mark_reusable_history_version!(version) if automatic
    version
  end

  def self.snapshot_for(idea)
    {
      "title" => idea.title,
      "state" => idea.state,
      "category" => idea.category,
      "template_id" => idea.template_id,
      "topology_ids" => idea.idea_topologies.order(:topology_id).pluck(:topology_id),
      "list_memberships" => idea.idea_lists.order(:list_id).map { |membership| idea_list_snapshot(membership) },
      "trl" => idea.trl,
      "difficulty" => idea.difficulty,
      "opportunity" => idea.opportunity,
      "timing" => idea.timing,
      "computed_score" => idea.computed_score&.to_f,
      "attempt_count" => idea.attempt_count,
      "cool_off_until" => serialize_time(idea.cool_off_until),
      "description" => idea.description.to_plain_text,
      "metadata" => normalize_json(idea.metadata),
      "difficulty_explanation" => idea.difficulty_explanation,
      "opportunity_explanation" => idea.opportunity_explanation,
      "timing_explanation" => idea.timing_explanation,
      "email_ingested" => idea.email_ingested,
      "integrity_hash" => idea.integrity_hash,
      "discarded_at" => serialize_time(idea.discarded_at),
      "draft" => idea.draft,
      "napkin_calculations" => normalize_json(idea.napkin_calculations),
      "todo_items" => idea.todo_items.order(:position, :id).map { |todo| todo_item_snapshot(todo) },
      "notes" => idea.notes.order(:depth, :created_at, :id).map { |note| note_snapshot(note) },
      "idea_entries" => idea.idea_entries.order(:kind, :position, :id).map { |entry| idea_entry_snapshot(entry) },
      "drawings" => idea.drawings.order(:role, :position, :id).map { |drawing| drawing_snapshot(drawing) },
      "media" => {
        "hero_image" => attachment_snapshot(idea.hero_image),
        "attachments" => idea.attachments.map { |attachment| attachment_snapshot(attachment) }
      }
    }
  end

  def self.snapshots_equal?(left, right)
    normalize_json(left) == normalize_json(right)
  end

  # Generate snapshot of the idea's current state
  def generate_snapshot
    return unless idea

    self.snapshot_data = self.class.snapshot_for(idea)
  end

  # Generate diff summary comparing to parent version
  def generate_diff_summary
    return unless parent_version

    self.diff_summary = self.class.diff_summary_for(snapshot_data, parent_version.snapshot_data)
  end

  # Compare this version with another version
  def diff_with(other_version)
    return {} unless other_version

    differences = {}
    other_data = other_version.snapshot_data

    snapshot_data.each do |key, value|
      other_value = other_data[key]
      if other_value != value
        differences[key] = {
          from: other_value,
          to: value
        }
      end
    end

    differences
  end

  # Restore this version to the idea (creates a new branch)
  def restore_to_idea!
    idea.transaction do
      Idea.without_history_tracking do
        restore_idea_attributes!
        restore_topologies!
        restore_lists!
        restore_todo_items!
        restore_notes!
        restore_idea_entries!
        restore_drawings!
        restore_media!
      end

      # Create a new version to record the restoration
      Version.create_from_idea(
        idea,
        "Restored from version #{id} (#{commit_message})",
        self,
        force: true
      )

      true
    end
  end

  # Get the version tree path from root to this version
  def ancestry_path
    path = [self]
    current = self

    while current.parent_version.present?
      current = current.parent_version
      path.unshift(current)
    end

    path
  end

  # Get scoring-related changes in this version
  def scoring_changes
    return {} unless parent_version

    scoring_fields = %w[trl difficulty opportunity timing computed_score]
    changes = {}
    
    parent_data = parent_version.snapshot_data
    current_data = snapshot_data

    scoring_fields.each do |field|
      parent_value = parent_data[field]
      current_value = current_data[field]
      
      if parent_value != current_value
        changes[field] = {
          from: parent_value,
          to: current_value,
          change: (current_value || 0).to_f - (parent_value || 0).to_f
        }
      end
    end

    changes
  end

  # Check if this version contains scoring changes
  def has_scoring_changes?
    scoring_changes.any?
  end

  # Get the computed score for this version
  def computed_score
    snapshot_data['computed_score']
  end

  # Get scoring metrics for this version
  def scoring_metrics
    {
      trl: snapshot_data['trl'],
      difficulty: snapshot_data['difficulty'],
      opportunity: snapshot_data['opportunity'],
      timing: snapshot_data['timing'],
      computed_score: snapshot_data['computed_score']
    }
  end

  # Compare scoring metrics with another version
  def scoring_diff_with(other_version)
    return {} unless other_version

    scoring_fields = %w[trl difficulty opportunity timing computed_score]
    differences = {}
    other_data = other_version.snapshot_data

    scoring_fields.each do |field|
      my_value = snapshot_data[field]
      other_value = other_data[field]
      
      if my_value != other_value
        differences[field] = {
          from: other_value,
          to: my_value,
          change: (my_value || 0).to_f - (other_value || 0).to_f
        }
      end
    end

    differences
  end

  # Check if this is a root version (no parent)
  def root?
    parent_version_id.nil?
  end

  # Check if this version has children (branches)
  def has_branches?
    child_versions.any?
  end

  # Get all descendant versions
  def descendants
    children = child_versions.to_a
    children + children.flat_map(&:descendants)
  end

  private

  def self.idea_list_snapshot(membership)
    {
      "id" => membership.id,
      "list_id" => membership.list_id,
      "position" => membership.position,
      "created_at" => serialize_time(membership.created_at),
      "updated_at" => serialize_time(membership.updated_at)
    }
  end

  def self.todo_item_snapshot(todo)
    {
      "id" => todo.id,
      "title" => todo.title,
      "position" => todo.position,
      "completed" => todo.completed,
      "completed_at" => serialize_time(todo.completed_at),
      "created_at" => serialize_time(todo.created_at),
      "updated_at" => serialize_time(todo.updated_at)
    }
  end

  def self.note_snapshot(note)
    {
      "id" => note.id,
      "parent_note_id" => note.parent_note_id,
      "body" => note.body,
      "depth" => note.depth,
      "created_at" => serialize_time(note.created_at),
      "updated_at" => serialize_time(note.updated_at)
    }
  end

  def self.idea_entry_snapshot(entry)
    {
      "id" => entry.id,
      "kind" => entry.kind,
      "name" => entry.name,
      "url" => entry.url,
      "description" => entry.description,
      "position" => entry.position,
      "created_at" => serialize_time(entry.created_at),
      "updated_at" => serialize_time(entry.updated_at)
    }
  end

  def self.drawing_snapshot(drawing)
    {
      "id" => drawing.id,
      "title" => drawing.title,
      "role" => drawing.role,
      "position" => drawing.position,
      "content" => normalize_json(drawing.content),
      "rendered_png" => attachment_snapshot(drawing.rendered_png),
      "created_at" => serialize_time(drawing.created_at),
      "updated_at" => serialize_time(drawing.updated_at)
    }
  end

  def self.attachment_snapshot(attachment)
    return nil unless attachment

    attachment = attachment.attachment if attachment.respond_to?(:attachment)
    return nil unless attachment

    blob = attachment.blob
    {
      "attachment_id" => attachment.id,
      "blob_id" => blob.id,
      "filename" => blob.filename.to_s,
      "content_type" => blob.content_type,
      "byte_size" => blob.byte_size,
      "checksum" => blob.checksum,
      "created_at" => serialize_time(blob.created_at)
    }
  end

  def self.diff_summary_for(current_data, parent_data)
    return nil unless parent_data

    changes = []
    normalize_json(current_data).each do |key, value|
      parent_value = normalize_json(parent_data)[key]
      changes << "#{key}: #{parent_value.inspect} -> #{value.inspect}" if parent_value != value
    end

    changes.join("\n")
  end

  def self.normalize_json(value)
    return nil if value.nil?

    JSON.parse(JSON.generate(value))
  end

  def self.serialize_time(value)
    value&.iso8601
  end

  def restore_idea_attributes!
    idea.assign_attributes(
      title: snapshot_data["title"],
      state: snapshot_data["state"],
      category: snapshot_data["category"],
      template_id: snapshot_data["template_id"],
      trl: snapshot_data["trl"],
      difficulty: snapshot_data["difficulty"],
      opportunity: snapshot_data["opportunity"],
      timing: snapshot_data["timing"],
      attempt_count: snapshot_data["attempt_count"],
      cool_off_until: parse_time(snapshot_data["cool_off_until"]),
      metadata: snapshot_data["metadata"],
      difficulty_explanation: snapshot_data["difficulty_explanation"],
      opportunity_explanation: snapshot_data["opportunity_explanation"],
      timing_explanation: snapshot_data["timing_explanation"],
      email_ingested: snapshot_data["email_ingested"],
      integrity_hash: snapshot_data["integrity_hash"],
      discarded_at: parse_time(snapshot_data["discarded_at"]),
      draft: snapshot_data["draft"],
      napkin_calculations: snapshot_data["napkin_calculations"]
    )
    idea.description = snapshot_data["description"].to_s if snapshot_data.key?("description")
    idea.save!
  end

  def restore_topologies!
    idea.idea_topologies.destroy_all
    Array(snapshot_data["topology_ids"]).each do |topology_id|
      next unless Topology.exists?(topology_id)

      idea.idea_topologies.create!(topology_id: topology_id)
    end
  end

  def restore_lists!
    idea.idea_lists.destroy_all
    Array(snapshot_data["list_memberships"]).each do |attributes|
      next unless List.exists?(attributes["list_id"])

      idea.idea_lists.create!(
        list_id: attributes["list_id"],
        position: attributes["position"]
      )
    end
  end

  def restore_todo_items!
    idea.todo_items.destroy_all
    Array(snapshot_data["todo_items"]).each do |attributes|
      idea.todo_items.create!(
        title: attributes["title"],
        position: attributes["position"],
        completed: attributes["completed"],
        completed_at: parse_time(attributes["completed_at"])
      )
    end
  end

  def restore_notes!
    idea.notes.destroy_all
    id_map = {}

    Array(snapshot_data["notes"]).sort_by { |attributes| [attributes["depth"].to_i, attributes["created_at"].to_s, attributes["id"].to_i] }.each do |attributes|
      note = idea.notes.create!(
        body: attributes["body"],
        parent_note_id: id_map[attributes["parent_note_id"]],
        depth: attributes["depth"] || 0
      )
      id_map[attributes["id"]] = note.id
    end
  end

  def restore_idea_entries!
    idea.idea_entries.destroy_all
    Array(snapshot_data["idea_entries"]).each do |attributes|
      idea.idea_entries.create!(
        kind: attributes["kind"],
        name: attributes["name"],
        url: attributes["url"],
        description: attributes["description"],
        position: attributes["position"]
      )
    end
  end

  def restore_drawings!
    idea.drawings.destroy_all
    Array(snapshot_data["drawings"]).each do |attributes|
      drawing = idea.drawings.create!(
        title: attributes["title"],
        role: attributes["role"],
        position: attributes["position"],
        content: attributes["content"]
      )
      attach_blob(drawing.rendered_png, attributes["rendered_png"])
    end
  end

  def restore_media!
    idea.hero_image.detach
    attach_blob(idea.hero_image, snapshot_data.dig("media", "hero_image"))

    idea.attachments.detach
    Array(snapshot_data.dig("media", "attachments")).each do |attachment_data|
      attach_blob(idea.attachments, attachment_data)
    end
  end

  def attach_blob(attachment_proxy, attachment_data)
    return unless attachment_data

    blob = ActiveStorage::Blob.find_by(id: attachment_data["blob_id"])
    attachment_proxy.attach(blob) if blob
  end

  def parse_time(value)
    return nil if value.blank?

    Time.zone.parse(value.to_s)
  end
end
