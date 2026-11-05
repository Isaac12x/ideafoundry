# Hero becomes an ordered mix of uploaded images (hero_images) and hero drawings.
# hero_order holds keys ("image:<blob_id>", "drawing:<id>"); unknown/stale keys are ignored.
class AddHeroOrderAndRenameHeroImage < ActiveRecord::Migration[8.1]
  def up
    add_column :ideas, :hero_order, :json, default: [], null: false
    execute <<~SQL
      UPDATE active_storage_attachments SET name = 'hero_images'
      WHERE record_type = 'Idea' AND name = 'hero_image'
    SQL
  end

  def down
    execute <<~SQL
      UPDATE active_storage_attachments SET name = 'hero_image'
      WHERE record_type = 'Idea' AND name = 'hero_images'
        AND id IN (SELECT MIN(id) FROM active_storage_attachments
                   WHERE record_type = 'Idea' AND name = 'hero_images' GROUP BY record_id)
    SQL
    remove_column :ideas, :hero_order
  end
end
