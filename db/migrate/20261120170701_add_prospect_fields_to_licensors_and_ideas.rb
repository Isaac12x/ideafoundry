class AddProspectFieldsToLicensorsAndIdeas < ActiveRecord::Migration[8.0]
  def change
    add_column :licensors, :channel, :string # where / how to approach (trade show, agent, cold email...)
    add_column :ideas, :licensing_notes, :text # free-form "where and whom to license" scratchpad
  end
end
