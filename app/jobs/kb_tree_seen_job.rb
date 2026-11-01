# Clears the "new download" dot in every open tab. Runs after the response: a full tree rebuild and re-render
# (thousands of rows) must never sit in the request that opens a file, nor re-render the open tabs' whole tree.
class KbTreeSeenJob < ApplicationJob
  queue_as :default

  def perform(user_id, folder_index, rel_path)
    user = User.find_by(id: user_id) or return
    rel = rel_path.to_s.gsub(/["\\]/) { |char| "\\#{char}" }
    Turbo::StreamsChannel.broadcast_action_to([ user, "kb_tree" ], action: :kb_seen,
      targets: %(.kb-file-row[data-kb-tree-src-param="#{folder_index.to_i}"][data-kb-tree-rel-param="#{rel}"]))
  end
end
