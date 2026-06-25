module TracksActivity
  extend ActiveSupport::Concern

  SYSTEM_FIELDS = %w[updated_at created_at].freeze

  class_methods do
    def tracks_activity(name_method: :name, ignore_fields: [])
      class_attribute :_activity_name_method,   default: name_method
      class_attribute :_activity_ignore_fields, default: SYSTEM_FIELDS + Array(ignore_fields).map(&:to_s)

      after_create  -> { log_activity("created") }
      after_update  -> { log_activity("updated") }
      after_destroy -> { log_activity("destroyed") }
    end
  end

  def activity_display_name
    send(self.class._activity_name_method)
  rescue StandardError
    nil
  end

  private

  def log_activity(action)
    return if ActivityLog.tracking_suppressed?

    owner = activity_user
    return unless owner

    details = {}
    if action == "updated"
      changed = saved_changes.except(*self.class._activity_ignore_fields).keys
      return if changed.empty?
      details[:changed] = changed
    end

    ActivityLog.create!(
      user:           owner,
      actor:          Thread.current[:activity_actor] || "user",
      action:         action,
      trackable_type: self.class.name,
      trackable_id:   id,
      trackable_name: activity_display_name,
      details:        details
    )
  rescue => e
    Rails.logger.error "TracksActivity #{self.class.name}##{id}: #{e.message}"
  end

  def activity_user
    if respond_to?(:user) && association(:user).loaded?
      user
    elsif respond_to?(:user_id) && user_id.present?
      User.find_by(id: user_id)
    end
  end
end
