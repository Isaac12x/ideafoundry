# Converts one KB ebook into its hidden sidecar (see Kb::BookConversion). The controller claimed the lock.
class KbBookConvertJob < ApplicationJob
  queue_as :default

  def perform(abs)
    # Project is locking: write nothing, free the claim; the Convert button works again afterwards.
    return FileUtils.rm_f(Kb::BookConversion.state_file(abs, "lock")) if Kb::ProjectLock.busy_path?(abs)

    Kb::BookConversion.convert!(abs)
  rescue Kb::BookConversion::Error, SystemCallError => e
    Rails.logger.warn("KbBookConvertJob #{abs}: #{e.message}")
    FileUtils.mkdir_p(Kb::BookConversion.state_dir)
    File.write(Kb::BookConversion.state_file(abs, "err"), e.message.truncate(300))
  end
end
