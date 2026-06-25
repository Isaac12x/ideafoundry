class ActivityLog < ApplicationRecord
  belongs_to :user
  belongs_to :trackable, polymorphic: true, optional: true

  serialize :details, coder: JSON

  ACTORS  = %w[user server agent].freeze
  ACTIONS = %w[created updated destroyed restored settings_changed].freeze

  validates :actor,  inclusion: { in: ACTORS }
  validates :action, presence: true

  scope :recent,              -> { order(created_at: :desc) }
  scope :for_trackable_type,  ->(type) { where(trackable_type: type) }

  def self.record!(user:, actor: "user", action:, trackable: nil, trackable_name: nil, details: {})
    return if tracking_suppressed?

    create!(
      user:           user,
      actor:          actor,
      action:         action,
      trackable:      trackable,
      trackable_name: trackable_name || trackable.try(:activity_display_name),
      details:        details
    )
  rescue => e
    Rails.logger.error "ActivityLog.record! failed: #{e.message}"
  end

  def self.record_settings!(user:, setting:, details: {})
    return if tracking_suppressed?

    create!(
      user:           user,
      actor:          "user",
      action:         "settings_changed",
      trackable_type: "Settings",
      trackable_name: setting,
      details:        details
    )
  rescue => e
    Rails.logger.error "ActivityLog.record_settings! failed: #{e.message}"
  end

  def self.without_tracking
    prev = Thread.current[:activity_log_suppressed]
    Thread.current[:activity_log_suppressed] = true
    yield
  ensure
    Thread.current[:activity_log_suppressed] = prev
  end

  def self.tracking_suppressed?
    Thread.current[:activity_log_suppressed]
  end

  def actor_label
    case actor
    when "agent"  then "AI Agent"
    when "server" then "Server"
    else               "You"
    end
  end

  def action_verb
    case action
    when "created"         then "created"
    when "updated"         then "updated"
    when "destroyed"       then "deleted"
    when "restored"        then "restored"
    when "settings_changed" then "changed"
    else action.humanize.downcase
    end
  end

  def trackable_kind_label
    case trackable_type
    when "Settings"    then "settings"
    when "Idea"        then "idea"
    when "List"        then "list"
    when "KanbanBoard" then "board"
    when "Topology"    then "topology"
    when "Submission"  then "intake submission"
    when "Template"    then "template"
    else trackable_type&.underscore&.humanize&.downcase
    end
  end
end
