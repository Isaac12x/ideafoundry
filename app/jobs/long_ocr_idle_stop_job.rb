# Stops the heavy on-demand OCR backend once it has been idle. Scheduled
# frequently via Solid Queue recurring; a no-op when the backend is remote,
# already down, or a job is still in flight.
class LongOcrIdleStopJob < ApplicationJob
  queue_as :default

  def perform
    return if KnowledgeExtraction.active?

    backend = LongOcr::Backend.current
    return unless backend.manages_lifecycle?

    supervisor = LongOcr::ServiceSupervisor.new(backend: backend)
    return unless supervisor.ready?

    idle_timeout = ENV.fetch("OCR_LONG_IDLE_TIMEOUT", "300").to_i
    last_finished = KnowledgeExtraction.where.not(finished_at: nil).maximum(:finished_at)
    return if last_finished && last_finished > idle_timeout.seconds.ago

    supervisor.stop!
  end
end
