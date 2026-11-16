require "test_helper"

class IdeaDependencyTest < ActiveSupport::TestCase
  setup do
    @a = ideas(:one)
    @b = ideas(:two)
    @c = ideas(:three)
  end

  def token(idea) = "@[#{idea.title}](idea:#{idea.id})"

  test "mention tokens add and remove prerequisites" do
    @a.update!(tldr: "after #{token(@b)} and #{token(@c)}")
    assert_equal [ @b.id, @c.id ].sort, @a.prerequisites.pluck(:id).sort

    @a.update!(tldr: "only #{token(@c)}")
    assert_equal [ @c.id ], @a.prerequisites.reload.pluck(:id)
    assert_equal [ @a.id ], @c.dependents.pluck(:id)
  end

  test "description tokens are synced" do
    @a.update!(description: "<p>needs #{token(@b)}</p>")
    assert_includes @a.prerequisites.pluck(:id), @b.id
  end

  test "rejects self and cross-user ideas" do
    other = User.create!(email: "x@example.com", name: "X").ideas.create!(title: "Foreign", state: :idea_new, attempt_count: 0)
    @a.update!(tldr: "#{token(@a)} #{token(other)}")
    assert_empty @a.prerequisites.reload
    assert_not IdeaDependency.new(idea: @a, prerequisite: other).valid?
    assert_not IdeaDependency.new(idea: @a, prerequisite: @a).valid?
  end
end
