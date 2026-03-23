class ExpireSubmissionsJob < ApplicationJob
  queue_as :default

  def perform
    Submission.stale.find_each do |submission|
      submission.update!(status: :expired)
    end
  end
end
