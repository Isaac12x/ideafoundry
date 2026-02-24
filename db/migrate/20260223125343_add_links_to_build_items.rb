class AddLinksToBuildItems < ActiveRecord::Migration[8.0]
  def change
    add_column :build_items, :links, :text
  end
end
