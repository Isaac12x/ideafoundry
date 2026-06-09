class NormalizeSerializedUserSettings < ActiveRecord::Migration[8.0]
  class MigrationUser < ActiveRecord::Base
    self.table_name = "users"
    serialize :settings, coder: JSON
  end

  def up
    MigrationUser.find_each do |user|
      normalized = normalize_settings_value(user.settings)
      next if user.settings == normalized

      user.update_columns(settings: normalized)
    end
  end

  def down
    # Data normalization only.
  end

  private

  def normalize_settings_value(value)
    current = value

    3.times do
      return current if current.is_a?(Hash)
      return {} if current.blank?
      return {} unless current.is_a?(String)

      current = JSON.parse(current)
    rescue JSON::ParserError
      return {}
    end

    current.is_a?(Hash) ? current : {}
  end
end
