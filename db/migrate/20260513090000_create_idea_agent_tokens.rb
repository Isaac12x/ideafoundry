class CreateIdeaAgentTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :idea_agent_tokens do |t|
      t.references :idea, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :name, null: false
      t.datetime :last_used_at
      t.datetime :expires_at
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :idea_agent_tokens, :token_digest, unique: true
    add_index :idea_agent_tokens, [:idea_id, :active]
  end
end
