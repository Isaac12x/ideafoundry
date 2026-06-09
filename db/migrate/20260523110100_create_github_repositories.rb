class CreateGithubRepositories < ActiveRecord::Migration[8.0]
  def change
    create_table :github_repositories do |t|
      t.references :idea, null: false, foreign_key: true, index: { unique: true }
      t.string :repository_url, null: false
      t.string :owner, null: false
      t.string :name, null: false
      t.string :default_branch
      t.boolean :private, null: false, default: false
      t.boolean :has_releases, null: false, default: false
      t.string :latest_release_tag
      t.string :latest_release_url
      t.datetime :last_checked_at
      t.text :last_error

      t.timestamps
    end

    add_index :github_repositories, [:owner, :name]
    add_index :github_repositories, :has_releases
  end
end
