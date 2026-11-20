# Live-editable connection settings: non-blank DB value (ServiceSetting) beats ENV beats default.
# Read per call (sqlite, cheap) so every Puma worker and the jobs process see edits at once.
# Quacks like ENV ([] / fetch) so LongOcr::Backend can take `env: ServiceSettings`.
module ServiceSettings
  module_function

  def fetch(key, default = nil) = db_value(key).presence || ENV[key].presence || default

  def [](key) = fetch(key)

  def source(key)
    if db_value(key).present? then "settings"
    elsif ENV[key].present? then "env"
    else "unset"
    end
  end

  def db_value(key)
    ServiceSetting.where(key: key.to_s).pick(:value)
  rescue ActiveRecord::ActiveRecordError
    nil # table missing before migrate: ENV only
  end
end
