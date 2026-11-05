class AddOrderingToKbEntryPreferences < ActiveRecord::Migration[8.1]
  def change
    add_column :kb_entry_preferences, :sort_mode, :string
    add_column :kb_entry_preferences, :manual_order, :text
  end
end
