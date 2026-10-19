class AddTokenToApiKeys < ActiveRecord::Migration[8.0]
  def change
    add_column :api_keys, :token, :text
  end
end
