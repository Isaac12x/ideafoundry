require "test_helper"

class Kb::SubprocessTest < ActiveSupport::TestCase
  test "captures output and status" do
    out, _err, status = Kb::Subprocess.capture("echo", "hi", timeout: 5)
    assert_equal "hi\n", out
    assert status.success?
  end

  test "kills a command that outlives its timeout" do
    started = Time.now
    assert_raises(Kb::Subprocess::Timeout) { Kb::Subprocess.capture("sleep", "30", timeout: 0.3) }
    assert_operator Time.now - started, :<, 5
  end
end
