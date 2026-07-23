require "test_helper"
require "fileutils"
require "open3"
require "socket"
require "tmpdir"

class DevLauncherTest < ActiveSupport::TestCase
  DEV_SCRIPT = Rails.root.join("bin/dev").to_s

  setup do
    @fake_bin = Dir.mktmpdir("idea-foundry-dev-launcher")
    write_executable("gem", <<~SH)
      #!/bin/sh
      exit 0
    SH
    write_executable("foreman", <<~SH)
      #!/bin/sh
      printf '%s\n' "$@"
    SH
  end

  teardown do
    FileUtils.remove_entry(@fake_bin)
  end

  test "uses the preferred port when it is available" do
    preferred_port = available_port

    stdout, stderr, status = run_dev(env: { "PORT" => preferred_port.to_s })

    assert status.success?, stderr
    assert_equal ["start", "-f", "Procfile.dev", "-p", preferred_port.to_s], stdout.lines(chomp: true)
  end

  test "selects another port when the preferred port is occupied" do
    listener = TCPServer.new("127.0.0.1", 0)
    occupied_port = listener.local_address.ip_port

    stdout, stderr, status = run_dev(env: { "PORT" => occupied_port.to_s })
    lines = stdout.lines(chomp: true)
    selected_port = Integer(lines.last)

    assert status.success?, stderr
    assert_operator selected_port, :>, occupied_port
    assert_includes lines.first, "Port #{occupied_port} is already in use"
    assert_equal ["start", "-f", "Procfile.dev", "-p", selected_port.to_s], lines.last(5)
  ensure
    listener&.close
  end

  test "preserves an explicit Foreman port override" do
    stdout, stderr, status = run_dev("-p", "4567", env: { "PORT" => "3000" })

    assert status.success?, stderr
    assert_equal ["start", "-f", "Procfile.dev", "-p", "4567"], stdout.lines(chomp: true)
  end

  private

  def available_port
    listener = TCPServer.new("127.0.0.1", 0)
    listener.local_address.ip_port
  ensure
    listener&.close
  end

  def run_dev(*arguments, env: {})
    Open3.capture3(
      env.merge("PATH" => "#{@fake_bin}:#{ENV.fetch('PATH')}"),
      DEV_SCRIPT,
      *arguments,
      chdir: Rails.root.to_s
    )
  end

  def write_executable(name, contents)
    path = File.join(@fake_bin, name)
    File.write(path, contents)
    FileUtils.chmod(0o755, path)
  end
end
