# Named lists hold anything: free text, a link, or a KB entry (stored as its title + in-app URL), next to ideas.
class CreateListItems < ActiveRecord::Migration[8.1]
  def change
    create_table :list_items do |t|
      t.references :list, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url
      t.integer :position, null: false
      t.timestamps
    end
  end
end
