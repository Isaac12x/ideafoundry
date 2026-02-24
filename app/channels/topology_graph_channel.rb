class TopologyGraphChannel < ApplicationCable::Channel
  def subscribed
    stream_from "topology_graph:#{current_user.id}"
  end
end
