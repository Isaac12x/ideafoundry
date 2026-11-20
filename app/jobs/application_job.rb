class ApplicationJob < ActiveJob::Base
  # bin/jobs is a long-lived separate process: honor passphrase changes made by the web workers
  # (RecoverySecret generation) before touching encrypted DBs.
  around_perform do |_job, block|
    RecoverySecret.reset_connections_if_changed!
    block.call
  end

  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError
end
