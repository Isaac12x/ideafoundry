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
  scope :chronological, -> { order(created_at: :asc) }

  # Create a new version from the current idea state
  def self.create_from_idea(idea, commit_message, parent_version = nil)
    create!(
      idea: idea,
      parent_version: parent_version || idea.versions.order(created_at: :desc).first,
      commit_message: commit_message
    )
  end

  # Generate snapshot of the idea's current state
  def generate_snapshot
    return unless idea

    self.snapshot_data = {
      title: idea.title,
      state: idea.state,
      topology_ids: idea.topology_ids,
      trl: idea.trl,
      difficulty: idea.difficulty,
      opportunity: idea.opportunity,
      timing: idea.timing,
      computed_score: idea.computed_score,
      attempt_count: idea.attempt_count,
      cool_off_until: idea.cool_off_until,
      description: idea.description.to_plain_text
    }
  end

  # Generate diff summary comparing to parent version
  def generate_diff_summary
    return unless parent_version

    changes = []
    parent_data = parent_version.snapshot_data
    current_data = snapshot_data

    # Exclude timestamps from diff
    excluded_keys = []

    current_data.each do |key, value|
      next if excluded_keys.include?(key)
      parent_value = parent_data[key]
      if parent_value != value
        changes << "#{key}: #{parent_value.inspect} → #{value.inspect}"
      end
    end

    self.diff_summary = changes.join("\n")
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
      # Update idea with snapshot data
      idea.assign_attributes(
        title: snapshot_data['title'],
        state: snapshot_data['state'],
        trl: snapshot_data['trl'],
        difficulty: snapshot_data['difficulty'],
        opportunity: snapshot_data['opportunity'],
        timing: snapshot_data['timing'],
      )

      # Restore topology associations if present in snapshot
      if snapshot_data['topology_ids'].is_a?(Array)
        idea.topology_ids = snapshot_data['topology_ids']
      end

      # Update description if present (stored as plain text, restore as plain text)
      if snapshot_data['description'].present?
        idea.description = snapshot_data['description']
      end

      idea.save!

      # Create a new version to record the restoration
      Version.create_from_idea(
        idea,
        "Restored from version #{id} (#{commit_message})",
        self
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
end
