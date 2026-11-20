class Notification < ApplicationRecord
  include NotificationScope

  belongs_to :user
  belongs_to :idea, optional: true

  validates :title, presence: true, length: { maximum: 255 }

  scope :unread, -> { where(read_at: nil) }
  scope :recent, -> { order(created_at: :desc, id: :desc) }

  # Other code calls this: Notification.notify!(scope: idea, title: "Scored", body: "...", url: idea_path(idea))
  def self.notify!(title:, scope: :general, body: nil, url: nil, user: User.first)
    create!(scope_attributes(scope).merge(user: user, title: title, body: body, url: url))
  end

  def read? = read_at.present?
  def mark_read!
    update!(read_at: Time.current) unless read?
  end
end
