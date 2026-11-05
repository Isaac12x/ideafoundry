# A user's named place in a paged KB document: a page (pdf, comic) or an epub CFI
# (`progress` 0..1 only orders those and labels them). Exactly one of page/cfi.
class KbBookmark < ApplicationRecord
  MAX_PER_FILE = 500
  MAX_LABEL = 120
  CFI_FORMAT = /\Aepubcfi\(.{1,2000}\)\z/m

  belongs_to :user

  before_validation do
    self.source_path = IdeaKbLink.normalize_source_path(source_path)
    self.relative_path = IdeaKbLink.normalize_relative_path(relative_path)
    self.label = label.to_s.squish
    self.cfi = cfi.presence
  end

  validates :source_path, :relative_path, presence: true
  validates :label, presence: true, length: { maximum: MAX_LABEL }
  validates :page, numericality: { only_integer: true, greater_than: 0, less_than: 1_000_000 }, allow_nil: true
  validates :cfi, format: { with: CFI_FORMAT }, allow_nil: true
  validates :progress, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 }, allow_nil: true
  validate :one_location
  validate :under_file_limit, on: :create

  scope :for_file, ->(source_path, relative_path) {
    where(source_path: IdeaKbLink.normalize_source_path(source_path),
          relative_path: IdeaKbLink.normalize_relative_path(relative_path))
  }
  scope :in_reading_order, -> { order(Arel.sql("COALESCE(page, 0)"), Arel.sql("COALESCE(progress, 0)"), :id) }

  class << self
    def move_subtree!(user:, source_path:, old_relative_path:, new_source_path:, new_relative_path:)
      old_rel = IdeaKbLink.normalize_relative_path(old_relative_path)
      new_rel = IdeaKbLink.normalize_relative_path(new_relative_path)
      new_source = IdeaKbLink.normalize_source_path(new_source_path)

      subtree(user, source_path, old_rel).find_each do |mark|
        suffix = mark.relative_path.delete_prefix(old_rel).delete_prefix("/")
        mark.update!(source_path: new_source, relative_path: suffix.present? ? File.join(new_rel, suffix) : new_rel)
      end
    end

    def delete_subtree!(user:, source_path:, relative_path:)
      subtree(user, source_path, IdeaKbLink.normalize_relative_path(relative_path)).delete_all
    end

    private

    def subtree(user, source_path, rel)
      user.kb_bookmarks
          .where(source_path: IdeaKbLink.normalize_source_path(source_path))
          .where("relative_path = ? OR relative_path LIKE ?", rel, "#{sanitize_sql_like(rel)}/%")
    end
  end

  def as_json(*)
    slice(:id, :label, :page, :cfi, :progress)
  end

  private

  def one_location
    errors.add(:base, "Bookmark needs a page or a book location, not both") unless page.present? ^ cfi.present?
  end

  def under_file_limit
    return unless user && self.class.where(user_id: user_id).for_file(source_path, relative_path).count >= MAX_PER_FILE

    errors.add(:base, "Too many bookmarks on this file (max #{MAX_PER_FILE})")
  end
end
