class ApiKey < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(active: true).where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :expired, -> { where("expires_at IS NOT NULL AND expires_at <= ?", Time.current) }

  attr_accessor :raw_token

  def self.generate(user:, name:, expires_at: nil)
    raw_token = SecureRandom.hex(32)
    key = create!(
      user: user,
      name: name,
      token_digest: Digest::SHA256.hexdigest(raw_token),
      expires_at: expires_at
    )
    key.raw_token = raw_token
    key
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?
    digest = Digest::SHA256.hexdigest(raw_token)
    key = active.find_by(token_digest: digest)
    if key
      key.update_column(:last_used_at, Time.current)
      key
    end
  end
end
