require "test_helper"

class CaptureJobTest < ActiveSupport::TestCase
  setup { @user = users(:one) }

  test "validates url and format" do
    assert_not @user.capture_jobs.new(url: "ftp://x.com").valid?
    assert_not @user.capture_jobs.new(url: "nope").valid?
    assert_not @user.capture_jobs.new(url: "https://x.com", file_format: "doc").valid?
    job = @user.capture_jobs.create!(url: "https://x.com")
    assert_equal "md", job.file_format
    assert_match(/\A\h{8}-/, job.public_id)
  end

  test "extension_url? matches chatgpt and claude hosts only" do
    %w[https://chatgpt.com/c/abc https://www.chatgpt.com/c/abc http://chat.openai.com/c/1 https://CLAUDE.ai/chat/x].each do |u|
      assert CaptureJob.extension_url?(u), u
    end
    [ "https://example.com/", "https://notclaude.ai/x", "ftp://claude.ai/x", "not a url", "" ].each do |u|
      assert_not CaptureJob.extension_url?(u), u
    end
  end

  test "as_extension_json includes source and directory" do
    job = @user.capture_jobs.create!(url: "https://claude.ai/chat/x", source_index: 1, dir: "ai/chats")
    assert_equal [ 1, "ai/chats" ], job.as_extension_json.values_at(:source, :directory)
    assert_not @user.capture_jobs.create!(url: "https://x.com").as_extension_json.key?(:source)
  end

  test "queue limit" do
    CaptureJob::ACTIVE_LIMIT.times { @user.capture_jobs.create!(url: "https://x.com") }
    assert_not @user.capture_jobs.new(url: "https://x.com").valid?
  end

  test "claim_next! takes oldest queued and marks running" do
    a = @user.capture_jobs.create!(url: "https://a.com", created_at: 2.minutes.ago)
    b = @user.capture_jobs.create!(url: "https://b.com", created_at: 1.minute.ago)
    assert_equal a, CaptureJob.claim_next!(@user)
    assert_equal "running", a.reload.state
    assert_not_nil a.claimed_at
    assert_equal b, CaptureJob.claim_next!(@user)
    assert_nil CaptureJob.claim_next!(@user)
  end

  test "expire_stale! fails old running jobs only" do
    old = @user.capture_jobs.create!(url: "https://a.com", state: "running", claimed_at: 6.minutes.ago)
    fresh = @user.capture_jobs.create!(url: "https://b.com", state: "running", claimed_at: 1.minute.ago)
    CaptureJob.expire_stale!
    assert_equal "failed", old.reload.state
    assert_equal CaptureJob::TIMEOUT_ERROR, old.error
    assert_equal "running", fresh.reload.state
  end
end
