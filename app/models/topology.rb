class Topology < ApplicationRecord
  FIELD_TYPES = Template::FIELD_TYPES
  SOFTWARE_GITHUB_FIELD = {
    "name" => "github_url",
    "label" => "GitHub URL",
    "type" => "url",
    "required" => false,
    "placeholder" => "https://github.com/owner/repository",
    "tab" => "general",
    "position" => 0,
    "instance_id" => "github_url"
  }.freeze

  belongs_to :user
  belongs_to :parent, class_name: 'Topology', optional: true
  has_many :children, class_name: 'Topology', foreign_key: :parent_id, dependent: :destroy
  has_many :idea_topologies, dependent: :destroy
  has_many :ideas, through: :idea_topologies

  serialize :default_field_definitions, coder: JSON

  enum :topology_type, { predefined: 0, custom: 1 }

  validates :name, presence: true, uniqueness: { scope: [:user_id, :parent_id] }
  validates :topology_type, presence: true
  validate :valid_default_field_definitions_format

  scope :roots, -> { where(parent_id: nil) }
  scope :by_parent, ->(parent) { where(parent_id: parent) }
  scope :ordered, -> { order(:position, :name) }

  before_validation :sanitize_default_field_definitions
  before_create :set_position
  after_commit :broadcast_graph_added, on: :create
  after_commit :broadcast_graph_updated, on: :update
  after_commit :broadcast_graph_removed, on: :destroy

  def ancestors
    path = []
    current = parent
    while current
      path.unshift(current)
      current = current.parent
    end
    path
  end

  def descendants
    children.to_a + children.flat_map(&:descendants)
  end

  def full_path
    (ancestors + [self]).map(&:name).join(' > ')
  end

  def depth
    ancestors.length
  end

  def root?
    parent_id.nil?
  end

  # Walk parent chain to find root topology. Caches per-request.
  def find_root
    @find_root ||= root? ? self : parent.find_root
  end

  def software?
    name.to_s.casecmp("software").zero?
  end

  def effective_default_field_definitions
    merge_field_definitions(built_in_default_field_definitions, default_field_definitions || [])
  end

  def self.sanitize_field_definitions(raw_definitions)
    Array(raw_definitions).filter_map.with_index do |raw_field, index|
      field = raw_field.respond_to?(:to_h) ? raw_field.to_h.stringify_keys : {}
      name = field["name"].to_s.strip.parameterize(separator: "_")
      next if name.blank?

      type = field["type"].to_s
      type = "text" unless FIELD_TYPES.include?(type)

      sanitized = {
        "name" => name,
        "label" => field["label"].presence || name.humanize,
        "type" => type,
        "required" => ActiveModel::Type::Boolean.new.cast(field["required"]) == true,
        "placeholder" => field["placeholder"].to_s.strip,
        "default_value" => field["default_value"].to_s,
        "tab" => field["tab"].presence || "general",
        "position" => field["position"].presence&.to_i || index,
        "instance_id" => field["instance_id"].presence || name
      }

      if type == "select"
        options = field["options"]
        sanitized["options"] = if options.is_a?(Array)
          options.map(&:to_s).map(&:strip).reject(&:blank?)
        else
          options.to_s.split(",").map(&:strip).reject(&:blank?)
        end
      end

      sanitized
    end
  end

  private

  def sanitize_default_field_definitions
    self.default_field_definitions = self.class.sanitize_field_definitions(default_field_definitions)
  end

  def valid_default_field_definitions_format
    return if default_field_definitions.blank?
    unless default_field_definitions.is_a?(Array)
      errors.add(:default_field_definitions, "must be an array")
      return
    end

    default_field_definitions.each_with_index do |field, index|
      unless field.is_a?(Hash)
        errors.add(:default_field_definitions, "field at index #{index} must be a hash")
        next
      end
      errors.add(:default_field_definitions, "field at index #{index} must have a name") if field["name"].blank?
      errors.add(:default_field_definitions, "field at index #{index} has invalid type") unless FIELD_TYPES.include?(field["type"])
    end
  end

  def built_in_default_field_definitions
    software? ? [SOFTWARE_GITHUB_FIELD.deep_dup] : []
  end

  def merge_field_definitions(*definition_sets)
    definition_sets.flatten.compact.each_with_object({}) do |field, merged|
      key = field["instance_id"].presence || field["name"]
      merged[key] = field
    end.values
  end

  def broadcast_graph_added
    root = find_root
    root_color = root.color.presence || '#d4953a'
    node = {
      id: "t_#{id}", name: name, color: color.presence || '#d4953a',
      type: 'topology', url: "/topologies/#{id}", val: 3,
      root_id: "t_#{root.id}", root_color: root_color
    }
    links = []
    links << { source: "t_#{parent_id}", target: "t_#{id}", type: 'parent' } if parent_id.present?

    ActionCable.server.broadcast("topology_graph:#{user_id}", { action: 'node_added', node: node, links: links })
  end

  def broadcast_graph_updated
    root = find_root
    root_color = root.color.presence || '#d4953a'
    node = {
      id: "t_#{id}", name: name, color: color.presence || '#d4953a',
      type: 'topology', url: "/topologies/#{id}", val: 3 + ideas.size,
      root_id: "t_#{root.id}", root_color: root_color
    }
    ActionCable.server.broadcast("topology_graph:#{user_id}", { action: 'node_updated', node: node })
  end

  def broadcast_graph_removed
    ActionCable.server.broadcast("topology_graph:#{user_id}", { action: 'node_removed', node_id: "t_#{id}" })
  end

  def set_position
    self.position ||= (user.topologies.maximum(:position) || 0) + 1
  end
end
