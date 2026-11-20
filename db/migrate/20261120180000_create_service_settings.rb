class CreateServiceSettings < ActiveRecord::Migration[8.1]
  def change
    create_table :service_settings do |t|
      t.string :key, null: false
      t.string :value
      t.timestamps
    end
    add_index :service_settings, :key, unique: true
  end
end
