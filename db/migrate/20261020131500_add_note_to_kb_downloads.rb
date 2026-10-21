class AddNoteToKbDownloads < ActiveRecord::Migration[8.1]
  def change
    # "Why are you saving this?" typed with the download; the job turns it into the file's .note.md sidecar.
    add_column :kb_downloads, :note, :text
  end
end
