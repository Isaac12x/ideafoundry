class AddOcrAndPositionToActiveStorageAttachments < ActiveRecord::Migration[8.0]
  def change
    add_column :active_storage_attachments, :position, :integer
    add_column :active_storage_attachments, :ocr_status, :string, null: false, default: "pending"
    add_column :active_storage_attachments, :ocr_text, :text
    add_column :active_storage_attachments, :ocr_metadata, :text
    add_column :active_storage_attachments, :ocr_error, :text

    add_index :active_storage_attachments, [:record_type, :record_id, :name, :position],
              name: "index_active_storage_attachments_on_record_position"
    add_index :active_storage_attachments, :ocr_status
  end
end
