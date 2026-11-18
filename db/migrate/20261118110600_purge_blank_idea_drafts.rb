class PurgeBlankIdeaDrafts < ActiveRecord::Migration[8.0]
  def up
    Idea.blank_drafts.each(&:destroy)
  end

  def down; end
end
