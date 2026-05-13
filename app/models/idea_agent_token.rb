class IdeaAgentToken < ApplicationRecord
  belongs_to :idea

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(active: true).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  attr_accessor :raw_token

  def self.generate(idea:, name:, expires_at: nil)
    raw_token = SecureRandom.hex(32)
    token = create!(
      idea: idea,
      name: name,
      token_digest: Digest::SHA256.hexdigest(raw_token),
      expires_at: expires_at
    )
    token.raw_token = raw_token
    token
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    active.find_by(token_digest: Digest::SHA256.hexdigest(raw_token)).tap do |token|
      token&.update_column(:last_used_at, Time.current)
    end
  end
end
