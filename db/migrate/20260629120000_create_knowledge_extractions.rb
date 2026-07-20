class CreateKnowledgeExtractions < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_extractions do |t|
      # lifecycle: pending/starting/processing/enriching/complete/failed/canceled
      t.integer :status, null: false, default: 0
      t.string :backend
      # "idea_attachment" or "kb_file"
      t.string :source_kind, null: false

      # idea source
      t.references :idea, null: true, foreign_key: true
      t.bigint :attachment_id, null: true
      t.bigint :output_attachment_id, null: true

      # kb source
      t.integer :kb_folder_index
      t.string :kb_path
      t.string :output_path

      t.string :source_filename
      t.integer :page_count
      t.integer :pages_done, null: false, default: 0
      t.text :markdown
      t.text :error
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end

    add_index :knowledge_extractions, :status
    add_index :knowledge_extractions, :attachment_id
  end
end
