# App-wide (not per-user) override for a sidecar/tool ENV key; see ServiceSettings.
class ServiceSetting < ApplicationRecord
  validates :key, presence: true, uniqueness: true
end
