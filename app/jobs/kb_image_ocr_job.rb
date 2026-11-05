# Background tesseract run for one KB image (see Kb::ImageOcr). The controller
# claimed the lock and validated the path; failures cache nothing and free the lock.
class KbImageOcrJob < ApplicationJob
  queue_as :default

  def perform(abs)
    Kb::ImageOcr.run!(abs) if File.file?(abs) && !Kb::ProjectLock.busy_path?(abs)
  rescue Kb::ImageOcr::Error => e
    Rails.logger.warn("KbImageOcrJob #{abs}: #{e.message}")
  end
end
