# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.
#
# Puma starts a configurable number of processes (workers) and each process
# serves each request in a thread from an internal thread pool.
#
# You can control the number of workers using ENV["WEB_CONCURRENCY"]. You
# should only set this value when you want to run 2 or more workers. The
# default is already 1. You can set it to `auto` to automatically start a worker
# for each available processor.
#
# The ideal number of threads per worker depends both on how much time the
# application spends waiting for IO operations and on how much you wish to
# prioritize throughput over latency.
#
# As a rule of thumb, increasing the number of threads will increase how much
# traffic a given process can handle (throughput), but due to CRuby's
# Global VM Lock (GVL) it has diminishing returns and will degrade the
# response time (latency) of the application.
#
# The default is set to 3 threads as it's deemed a decent compromise between
# throughput and latency for the average Rails application.
#
# Any libraries that use a connection pool or another resource pool should
# be configured to provide at least as many connections as the number of
# threads. This includes Active Record's `pool` parameter in `database.yml`.
# Production defaults to 6 worker processes (WEB_CONCURRENCY=1 -> single mode; dev stays single
# unless WEB_CONCURRENCY is set). SQLite has one writer, so cluster mode uses fewer threads per
# process (6x4 = 24 request threads in total); the busy handler in database.yml absorbs contention.
worker_count = Integer(ENV.fetch("WEB_CONCURRENCY", ENV["RAILS_ENV"] == "production" ? 6 : 1))
threads_count = ENV.fetch("RAILS_MAX_THREADS", worker_count > 1 ? 4 : 8) # Viewers issue parallel range requests; database.yml pool (default 8) must stay >= this.
threads threads_count, threads_count

if worker_count > 1
  workers worker_count
  # Load the app once in the master: workers fork copy-on-write and respawn fast. Active Record
  # discards inherited SQLite/SQLCipher handles after fork and each worker re-keys its own
  # connections from the keychain (RecoverySecret), so nothing secret is inherited or needed.
  preload_app!

  # Why this is large: the master compares WALL-CLOCK Time.now against each worker's last check-in
  # (Puma 8 cluster/worker_handle.rb). When macOS sleeps, everything freezes, the clock jumps on
  # wake, and the master kills every worker ("failed to check in within 60 seconds") before their
  # next ping is read. Must exceed the longest expected sleep. ponytail: hung-worker detection is
  # effectively off; lower via PUMA_WORKER_TIMEOUT if you never sleep the Mac.
  worker_timeout Integer(ENV.fetch("PUMA_WORKER_TIMEOUT", 7 * 24 * 3600))
  worker_boot_timeout Integer(ENV.fetch("PUMA_WORKER_BOOT_TIMEOUT", 7 * 24 * 3600))
end

worker_timeout 3600 if worker_count == 1 && ENV.fetch("RAILS_ENV", "development") == "development"

# Keep IPv4 binding for Docker, reverse proxies, and health checks (Puma 8 defaults to IPv6).
bind "tcp://#{ENV.fetch("PUMA_BIND_HOST", "0.0.0.0")}:#{ENV.fetch("PORT", 3000)}"

environment ENV.fetch("RAILS_ENV") { "development" }

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart

# Run the Solid Queue supervisor inside of Puma for single-server deployments.
plugin :solid_queue if ENV["SOLID_QUEUE_IN_PUMA"]

# Set the process title so it shows as "IdeaApp" instead of "ruby".
tag "IdeaApp"

# Specify the PID file. Defaults to tmp/pids/server.pid in development.
pidfile ENV.fetch("PIDFILE", "tmp/pids/server.pid")
