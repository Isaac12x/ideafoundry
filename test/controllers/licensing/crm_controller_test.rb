require "test_helper"

module Licensing
  class CrmControllerTest < ActionDispatch::IntegrationTest
    setup do
      @user = User.first || User.create!(email: "crm-test@example.com", name: "Test")
    end

    test "board view lists licensors of for-licensing ideas" do
      idea = @user.ideas.create!(title: "Licensable", for_licensing: true)
      idea.licensors.create!(company: "Acme")
      get licensing_crm_path
      assert_response :success
      assert_match "crm-board", response.body
      assert_match "Acme", response.body
    end

    test "table view renders grouped table" do
      idea = @user.ideas.create!(title: "Licensable", for_licensing: true)
      idea.licensors.create!(company: "Acme")
      get licensing_crm_path(view: "table")
      assert_response :success
      assert_match "crm-table", response.body
    end

    test "renders an empty state when nothing is flagged for licensing" do
      @user.ideas.where(for_licensing: true).destroy_all
      get licensing_crm_path
      assert_response :success
      assert_match "No ideas marked for licensing", response.body
    end
  end
end
