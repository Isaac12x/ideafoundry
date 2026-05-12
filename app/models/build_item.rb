class BuildItem < ApplicationRecord
  CHECKLIST_LINE_PATTERN = /\A(?<indent>\s*)(?<marker>[-*])\s+\[(?<state>[ xX])\]\s+(?<title>.*)\z/

  belongs_to :user

  validates :title, presence: true
  validate :completed_requires_complete_checklist

  # Store links as JSON array of {url, label} objects
  serialize :links, coder: JSON

  def links
    super || []
  end

  scope :pending, -> { where(completed: false).order(:position) }
  scope :done, -> { where(completed: true).order(completed_at: :desc) }

  before_validation :set_position, on: :create

  def mark_completed!
    update!(completed: true, completed_at: Time.current)
  end

  def mark_pending!
    update!(completed: false, completed_at: nil)
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
end
