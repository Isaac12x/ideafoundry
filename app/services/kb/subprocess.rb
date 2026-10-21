require "open3"

module Kb
  # Open3.capture3 with a wall-clock limit: the whole process group is killed on timeout.
  module Subprocess
    class Timeout < StandardError; end

    module_function

    # => [stdout, stderr, status]; raises Timeout.
    def capture(*cmd, timeout:)
      Open3.popen3(*cmd, pgroup: true) do |stdin, out, err, wait|
        stdin.close
        readers = [ out, err ].map { |io| Thread.new { io.read } }
        unless wait.join(timeout)
          Process.kill("KILL", -wait.pid) rescue nil # ponytail: group kill; falls back to nothing if already gone
          wait.join
          readers.each(&:kill)
          raise Timeout, "#{File.basename(cmd.first)} timed out after #{timeout.round}s"
        end
        [ readers[0].value, readers[1].value, wait.value ]
      end
    end
  end
end
