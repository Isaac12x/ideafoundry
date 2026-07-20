require "test_helper"

class LicensorTest < ActiveSupport::TestCase
  setup do
    @user = User.first || User.create!(email: "licensor-test@example.com", name: "Test")
    @idea = @user.ideas.create!(title: "Licensable Idea", for_licensing: true)
  end

  test "requires a company" do
    licensor = @idea.licensors.build(company: "")
    assert_not licensor.valid?
    assert licensor.errors[:company].present?
  end

  test "defaults to identified stage and assigns sequential position" do
    a = @idea.licensors.create!(company: "Acme")
    b = @idea.licensors.create!(company: "Globex")
    assert a.identified?
    assert_equal 1, a.position
    assert_equal 2, b.position
  end

  test "position is scoped per stage" do
    a = @idea.licensors.create!(company: "A")
    b = @idea.licensors.create!(company: "B", stage: :contacted)
    assert_equal 1, a.position
    assert_equal 1, b.position
  end

  test "rejects a malformed contact email but allows blank" do
    assert_not @idea.licensors.build(company: "Acme", contact_email: "nope").valid?
    assert @idea.licensors.build(company: "Acme", contact_email: "").valid?
  end

  test "open scope excludes closed licensors" do
    open = @idea.licensors.create!(company: "Open")
    @idea.licensors.create!(company: "Won", stage: :closed_won)
    @idea.licensors.create!(company: "Lost", stage: :closed_lost)
    assert_equal [open], @idea.licensors.open.to_a
  end

  test "stage metadata helpers" do
    assert_equal "Closed — Won", Licensor.stage_label("closed_won")
    assert_kind_of Integer, Licensor.stage_hue("identified")
    assert_equal 6, Licensor::STAGE_ORDER.size
  end

  test "closed? is true only for terminal stages" do
    assert_not @idea.licensors.create!(company: "A").closed?
    assert @idea.licensors.create!(company: "B", stage: :closed_lost).closed?
  end
end
