# A highlight or underline the user painted onto a KB document (pdf, docx,
# pptx, xlsx, html, markdown). Anchored by character offsets into the rendered
# text (per page for PDFs) plus the quoted text and a little context either
# side, so it can be re-found if the offsets drift. The quote is what the app
# reads back as "what the user found important" in this file.
class KbAnnotation < ApplicationRecord
  STYLES = %w[highlight underline].freeze
  COLORS = %w[yellow green pink blue].freeze
  MAX_QUOTE = 10_000
  MAX_CONTEXT = 64

  belongs_to :user

  before_validation do
    self.source_path = IdeaKbLink.normalize_source_path(source_path)
    self.relative_path = IdeaKbLink.normalize_relative_path(relative_path)
    self.prefix = prefix.to_s.last(MAX_CONTEXT)
    self.suffix = suffix.to_s.first(MAX_CONTEXT)
  end

  validates :source_path, :relative_path, :quote, presence: true
  validates :style, inclusion: { in: STYLES }
  validates :color, inclusion: { in: COLORS }
  validates :quote, length: { maximum: MAX_QUOTE }
  validates :start_offset, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :end_offset, numericality: { only_integer: true, greater_than: :start_offset }
  validates :page, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true

  scope :for_file, ->(source_path, relative_path) {
    where(source_path: IdeaKbLink.normalize_source_path(source_path),
          relative_path: IdeaKbLink.normalize_relative_path(relative_path))
  }
  scope :in_reading_order, -> { order(Arel.sql("COALESCE(page, 0)"), :start_offset) }

  class << self
    # Plain-text digest of a file's marks, for prompts and agent tools.
    def digest(user:, source_path:, relative_path:)
      marks = user.kb_annotations.for_file(source_path, relative_path).in_reading_order
      return "" if marks.empty?

      lines = marks.map { |mark| "- #{mark.page ? "[p.#{mark.page}] " : ""}#{mark.quote.squish}" }
      "User highlights (passages the user marked as important):\n#{lines.join("\n")}"
    end

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
      user.kb_annotations
          .where(source_path: IdeaKbLink.normalize_source_path(source_path))
          .where("relative_path = ? OR relative_path LIKE ?", rel, "#{sanitize_sql_like(rel)}/%")
    end
  end

  def as_json(*)
    slice(:id, :style, :color, :page, :start_offset, :end_offset, :quote, :prefix, :suffix)
  end
end
