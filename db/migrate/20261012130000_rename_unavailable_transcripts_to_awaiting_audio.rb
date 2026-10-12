class RenameUnavailableTranscriptsToAwaitingAudio < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE kb_downloads SET transcript_status = 'awaiting_audio' WHERE transcript_status = 'unavailable'"
  end

  def down
    execute "UPDATE kb_downloads SET transcript_status = 'unavailable' WHERE transcript_status = 'awaiting_audio'"
  end
end
