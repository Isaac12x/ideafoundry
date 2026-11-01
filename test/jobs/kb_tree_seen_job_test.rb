require "test_helper"

class KbTreeSeenJobTest < ActiveJob::TestCase
  include ActionCable::TestHelper

  test "broadcasts one small stream action naming the row, not the tree" do
    user = User.first || User.create!(email: "test@example.com", name: "Test")
    stream = Turbo::StreamsChannel.send(:stream_name_from, [ user, "kb_tree" ])

    assert_broadcasts(stream, 1) { KbTreeSeenJob.perform_now(user.id, 2, %(dir/we"ird.mp4)) }

    payload = CGI.unescapeHTML(JSON.parse(broadcasts(stream).first))
    assert_includes payload, 'action="kb_seen"'
    assert_includes payload, %(.kb-file-row[data-kb-tree-src-param="2"][data-kb-tree-rel-param="dir/we\\"ird.mp4"]) # quote escaped for the selector
    assert_operator payload.bytesize, :<, 600
  end

  test "a missing user is a no-op" do
    assert_nothing_raised { KbTreeSeenJob.perform_now(0, 0, "x.mp4") }
  end
end
