class Note < ApplicationRecord
  belongs_to :idea
  belongs_to :parent_note, class_name: "Note", optional: true
  has_many :replies, class_name: "Note", foreign_key: :parent_note_id, dependent: :destroy

  validates :body, presence: true

  before_create :set_depth

  scope :roots, -> { where(parent_note_id: nil) }
  scope :chronological, -> { order(created_at: :asc) }
  scope :recent_first, -> { order(created_at: :desc) }

  def root?
    parent_note_id.nil?
  end

  def has_replies?
    replies.exists?
  end

  def thread_count
    replies.count + replies.sum { |r| r.thread_count }
  end

  private

  def set_depth
    self.depth = parent_note ? parent_note.depth + 1 : 0
  end
end
