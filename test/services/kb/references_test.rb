require "test_helper"

class Kb::ReferencesTest < ActiveSupport::TestCase
  setup do
    @user = User.first || users(:one)
    @v1 = @user.ideas.create!(title: "Heat pump", state: :idea_new, attempt_count: 0)
    @v3 = @user.ideas.create!(title: "Heat pump", state: :idea_new, attempt_count: 0, version_group_id: @v1.id, version_number: 3)
  end

  test "parses typed tokens" do
    refs = Kb::References.parse("a @[Heat pump · v3](idea:7) b @[Rule](maxim:2) @[x](kb:0:file:a%20b.md) @[bad](nope:1)")
    assert_equal %w[idea maxim kb], refs.map(&:type)
    assert_equal "7", refs.first.ref
  end

  test "a version token links to that version's idea and shows the version in the chip" do
    html = Kb::References.linkify("see @[Heat pump](idea:#{@v3.id})", user: @user)
    assert_includes html, %(href="/ideas/#{@v3.id}")
    assert_includes html, "Heat pump · v3"
  end

  test "token round trip and escaping" do
    ref = Kb::References::Ref.new(label: "A [b]", type: "idea", ref: 4)
    assert_equal "@[A  b](idea:4)", ref.token
    assert_includes Kb::References.linkify("@[<script>](maxim:1)", user: @user), "&lt;script&gt;"
  end

  test "kb tokens decode the path and unknown ideas stay unlinked" do
    token = Kb::References::Ref.new(label: "n", type: "kb", ref: Kb::References.kb_ref(0, "file", "Docs/a b (1).md")).token
    html = Kb::References.linkify(token, user: @user)
    assert_includes html, "file=Docs%2Fa+b+%281%29.md"
    assert_includes Kb::References.linkify("@[Gone](idea:999999)", user: @user), "is-gone"
  end

  test "maxim, fact and problem chips deep-link to the card" do
    html = Kb::References.linkify("@[R](maxim:2) @[F](fact:7) @[P](problem:9)", user: @user)
    assert_includes html, %(href="/knowledge-base?tab=maxims#maxim_2")
    assert_includes html, %(href="/knowledge-base?tab=facts#fact_7")
    assert_includes html, %(href="/knowledge-base?tab=problems#problem_9")
  end

  test "tokens inside fenced blocks and inline code stay literal" do
    text = "```\n@[R](maxim:2)\n```\nafter @[A](maxim:3) and `@[B](maxim:4)` and\n~~~md\n@[C](maxim:5)\n~~~\n@[D](maxim:6)"
    html = Kb::References.linkify(text, user: @user)
    assert_includes html, "```\n@[R](maxim:2)\n```"
    assert_includes html, "`@[B](maxim:4)`"
    assert_includes html, "~~~md\n@[C](maxim:5)\n~~~"
    assert_equal %w[maxim_3 maxim_6], html.scan(/#(maxim_\d)/).flatten
  end
end
