class IdeaTopology < ApplicationRecord
  belongs_to :idea
  belongs_to :topology

  validates :topology_id, uniqueness: { scope: :idea_id }

  after_commit :broadcast_link_added, on: :create
  before_destroy :cache_broadcast_data
  after_commit :broadcast_link_removed, on: :destroy

  private

  def broadcast_link_added
    root = topology.find_root
    root_color = root.color.presence || '#d4953a'
    node = {
      id: "i_#{idea.id}", name: idea.title, color: '#9a9498',
      type: 'idea', url: "/ideas/#{idea.id}", val: 2,
      root_id: "t_#{root.id}", root_color: root_color
    }
    link = { source: "t_#{topology.id}", target: "i_#{idea.id}", type: 'idea' }
    ActionCable.server.broadcast("topology_graph:#{topology.user_id}", { action: 'link_added', node: node, link: link })
  end

  def cache_broadcast_data
    @cached_user_id = topology&.user_id
  end

  def broadcast_link_removed
    return unless @cached_user_id

    orphan = IdeaTopology.where(idea_id: idea_id).none?
    ActionCable.server.broadcast("topology_graph:#{@cached_user_id}", {
      action: 'link_removed',
      link_source: "t_#{topology_id}",
      link_target: "i_#{idea_id}",
      orphan_node_id: orphan ? "i_#{idea_id}" : nil
    })
  end
end
