class Topology < ApplicationRecord
  belongs_to :user
  belongs_to :parent, class_name: 'Topology', optional: true
  has_many :children, class_name: 'Topology', foreign_key: :parent_id, dependent: :destroy
  has_many :idea_topologies, dependent: :destroy
  has_many :ideas, through: :idea_topologies

  enum :topology_type, { predefined: 0, custom: 1 }

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :topology_type, presence: true

  scope :roots, -> { where(parent_id: nil) }
  scope :by_parent, ->(parent) { where(parent_id: parent) }
  scope :ordered, -> { order(:position, :name) }

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

  private

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
