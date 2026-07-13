module Kb
  class TreeBroadcaster
    def self.call(user)
      new(user).call
    end

    def initialize(user)
      @user = user
    end

    def call
      Turbo::StreamsChannel.broadcast_replace_to(
        [user, "kb_tree"],
        target: "kb-sidebar-tree",
        partial: "kb/tree",
        locals: {
          folders: TreeBuilder.new(user).call,
          selected_file: nil,
          selected_folder_index: nil
        }
      )
    rescue StandardError => error
      Rails.logger.error("KB tree broadcast failed: #{error.class}: #{error.message}")
      nil
    end

    private

    attr_reader :user
  end
end
