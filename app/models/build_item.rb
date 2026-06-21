class BuildItem < ApplicationRecord
  CHECKLIST_LINE_PATTERN = /\A(?<indent>\s*)(?<marker>[-*])\s+\[(?<state>[ xX])\]\s+(?<title>.*)\z/

  belongs_to :user
  has_many_attached :images

  validates :title, presence: true
  validate :images_are_images
  validate :completed_requires_complete_checklist

  # Store links as JSON array of {url, label} objects
  serialize :links, coder: JSON

  def links
    super || []
  end

  scope :pending, -> { where(completed: false).order(pinned: :desc, position: :asc) }
  scope :done, -> { where(completed: true).order(completed_at: :desc) }

  before_validation :set_position, on: :create

  def mark_completed!
    update!(completed: true, completed_at: Time.current)
  end

  def mark_pending!
    update!(completed: false, completed_at: nil)
  end

  # Aggregate checklist (subitem) counts across an already-loaded collection.
  # Returns { total:, done: } so callers avoid extra queries.
  def self.subitem_totals(items)
    items.reduce(total: 0, done: 0) do |acc, item|
      total = item.checklist_total_count
      { total: acc[:total] + total, done: acc[:done] + (total - item.checklist_remaining_count) }
    end
  end

  def self.parse_checklist_line(line)
    match = line.to_s.match(CHECKLIST_LINE_PATTERN)
    return unless match

    {
      indent: match[:indent],
      marker: match[:marker],
      completed: match[:state].match?(/\Ax\z/i),
      title: match[:title]
    }
  end

  def checklist_items
    description.to_s.lines(chomp: true).each_with_index.filter_map do |line, index|
      parsed = self.class.parse_checklist_line(line)
      next unless parsed

      parsed.merge(line_index: index)
    end
  end

  def checklist_total_count
    checklist_items.size
  end

  def checklist_remaining_count
    checklist_items.count { |item| !item[:completed] }
  end

  def checklist_complete?
    checklist_remaining_count.zero?
  end

  def checklist_blocking_completion?
    checklist_total_count.positive? && !checklist_complete?
  end

  # Soft-delete used by file-import reconciliation: drop the item to the "done"
  # section without running the checklist-completion validation or callbacks.
  def archive!
    update_columns(completed: true, completed_at: completed_at || Time.current, updated_at: Time.current)
  end

  # Join: absorb +other+ into this item as a checklist subitem, preserving its
  # own checklist lines (indented), links and images, then destroy +other+.
  def absorb!(other)
    raise ArgumentError, "cannot absorb self" if other.id == id

    appended = ["- [ ] #{other.title}"]
    other.description.to_s.lines(chomp: true).each do |line|
      appended << (line.empty? ? "" : "  #{line}")
    end

    base = description.to_s.sub(/\n+\z/, "")
    new_description = [base.presence, *appended].compact.join("\n")
    merged_links = (links + other.links).uniq { |link| link["url"] }

    transaction do
      other.images_attachments.update_all(record_id: id, record_type: "BuildItem") if other.images.attached?
      update!(description: new_description, links: merged_links)
      other.reload.destroy!
    end
  end

  def toggle_checklist_item!(line_index)
    index = Integer(line_index)
    lines = description.to_s.lines(chomp: true)
    return false if index.negative? || index >= lines.size

    parsed = self.class.parse_checklist_line(lines[index])
    return false unless parsed

    next_state = parsed[:completed] ? " " : "x"
    lines[index] = "#{parsed[:indent]}#{parsed[:marker]} [#{next_state}] #{parsed[:title]}"
    update!(description: lines.join("\n"))
  rescue ArgumentError, TypeError
    false
  end

  private

  def set_position
    return if position.present? || user.nil?
    max = user.build_items.maximum(:position) || 0
    self.position = max + 1
  end

  def completed_requires_complete_checklist
    return unless completed? && checklist_blocking_completion?

    errors.add(:completed, "requires all checklist items to be complete")
  end

  def images_are_images
    images.each do |image|
      next if image.content_type.to_s.start_with?("image/")

      errors.add(:images, "must be image files")
    end
  end
end
