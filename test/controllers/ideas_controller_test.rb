require "test_helper"

class IdeasControllerTest < ActionDispatch::IntegrationTest
  def setup
    # Use the same user that the controller will use (User.first)
    @user = User.first
    # Create an idea that belongs to this user
    @idea = @user.ideas.create!(
      title: "Test Idea",
      state: :idea_new
    )
  end

  test "should get index" do
    get ideas_url
    assert_response :success
  end

  test "index does not create planning records for an empty workspace" do
    empty_user = User.create!(email: "empty-ideas@example.com", name: "Empty Ideas")

    User.stub(:first, empty_user) do
      assert_no_difference [
        -> { empty_user.kanban_boards.count },
        -> { empty_user.lists.count },
        -> { empty_user.ideas.count }
      ] do
        get ideas_url
      end
    end

    assert_response :success
    assert_select ".empty-state", text: /No ideas found/
  end

  test "layout exposes global shortcuts, contextual cheatsheet, and command palette" do
    get ideas_url

    assert_response :success
    assert_select "body[data-controller~=?]", "shortcuts"
    assert_select "body[data-controller~=?]", "activity-panel", count: 0
    assert_select ".activity-panel", count: 0
    assert_select "body[data-shortcuts-ideas-url-value=?]", ideas_path
    assert_select ".kb-notes-tab-strip .shortcuts-toggle[title=?]", "Keyboard shortcuts", text: "⌘"
    assert_select ".shortcuts-panel[data-shortcuts-target=?]", "panel"
    assert_select ".command-palette[data-controller=?][data-command-palette-search-url-value=?]",
                  "command-palette", search_ideas_path
    assert_select ".app-dialog[data-controller=?][aria-labelledby=?]", "app-dialog", "app_dialog_title" do
      assert_select "form[data-app-dialog-target=?]", "form"
      assert_select "input[data-app-dialog-target=?]", "input"
      assert_select "button[data-app-dialog-target=?]", "confirmButton"
    end
    assert_select "a.nav-pill[data-shortcut-key=?][data-shortcut-label=?]", "g i", "Go to Ideas"
  end

  test "index renders right click list assignment hooks for idea cards" do
    @user.lists.create!(name: "Launch Candidates", kind: :named)

    get ideas_url

    assert_response :success
    assert_select ".ideas-container[data-controller~=?]", "idea-context-menu" do
      assert_select "[data-idea-context-menu-add-url-template-value=?]", "/ideas/__IDEA_ID__/add_to_list"
      assert_select "[data-idea-context-menu-named-lists-value*=?]", "Launch Candidates"
      assert_select "[data-idea-context-menu-kanban-boards-value*=?]", "Main Board"
    end
    assert_select ".idea-card[data-action*=?][data-idea-id=?]", "contextmenu->idea-context-menu#open", @idea.id.to_s
  end

  test "edit renders topologies as a searchable tree preserving template-switch hooks" do
    parent = @user.topologies.create!(name: "Software")
    @user.topologies.create!(name: "Web", parent: parent)

    get edit_idea_url(@idea)

    assert_response :success
    assert_select ".topology-picker[data-controller=?]", "topology-picker"
    assert_select "input.topology-picker__search"
    # Parent node nests the child underneath (recursion works).
    assert_select ".topology-node[data-topology-name=?]", "software" do
      assert_select ".topology-node[data-topology-name=?]", "software > web"
    end
    # Checkbox contract for template-switch must survive the new markup.
    assert_select "input[type=checkbox][name=?][data-template-switch-target=?]",
                  "idea[topology_ids][]", "topologyCheckbox", count: 2
  end

  test "should get new (auto-drafts and redirects to edit)" do
    assert_difference("Idea.where(draft: true).count", 1) do
      get new_idea_url
    end
    draft = Idea.where(draft: true).order(:created_at).last
    assert_redirected_to edit_idea_url(draft, draft: 1)
  end

  test "drafts are excluded from index" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true)
    get ideas_url
    assert_response :success
    assert_no_match draft.title, response.body
  end

  test "drafts are excluded from search" do
    @user.ideas.create!(title: "DraftSearchable", state: :idea_new, draft: true)
    get search_ideas_url(q: "DraftSearchable")
    assert_response :success
    json = JSON.parse(response.body)
    assert_empty json["results"]
  end

  test "updating a draft promotes it to a real idea" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true)
    patch idea_url(draft), params: { idea: { title: "Promoted" } }
    draft.reload
    refute draft.draft?
    assert_equal "Promoted", draft.title
  end

  test "saving a draft redirects to uncompleted ideas with client draft cleanup marker" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true)

    patch idea_url(draft), params: { idea: { title: "Promoted" } }

    assert_redirected_to uncompleted_ideas_url(idea_draft_saved: 1)
  end

  test "uncompleted ideas page lists unfinished drafts and recently started ideas" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true, updated_at: 2.minutes.ago)
    promoted = @user.ideas.create!(title: "Promoted", state: :idea_new, draft: false, created_at: 1.minute.ago, updated_at: 1.minute.ago)
    old = @user.ideas.create!(title: "Old Complete", state: :idea_new, draft: false, created_at: 2.days.ago, updated_at: 2.days.ago)

    get uncompleted_ideas_url

    assert_response :success
    assert_match draft.title, response.body
    assert_match promoted.title, response.body
    assert_no_match old.title, response.body
  end

  test "draft idea edit form enables delayed bottom-right uncompleted prompt" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true)

    get edit_idea_url(draft, draft: 1)

    assert_response :success
    assert_select ".idea-draft-resume.idea-draft-resume--toast", count: 1
    assert_select "[data-idea-draft-persist-prompt-delay-value=?]", "6000", count: 1
    assert_select "a[href=?]", uncompleted_ideas_path, text: /View Uncompleted/
  end

  test "draft idea edit form enables encrypted client draft persistence" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true)

    get edit_idea_url(draft, draft: 1)

    assert_response :success
    assert_select "form[data-controller~=?]", "idea-draft-persist", count: 1 do
      assert_select "[data-idea-draft-persist-target=?]", "prompt", count: 1
      assert_select "button[data-action*=?]", "idea-draft-persist#restore", count: 1
      assert_select "button[data-action*=?]", "idea-draft-persist#discard", count: 1
    end
  end

  test "draft idea edit form does not render list or board placement controls" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true)
    board = @user.kanban_boards.create!(name: "Validation")
    @user.lists.create!(name: "Queued", kind: :kanban, kanban_board: board)
    @user.lists.create!(name: "Launch Candidates", kind: :named)

    get edit_idea_url(draft, draft: 1)

    assert_response :success
    assert_select "label", text: "Kanban Boards", count: 0
    assert_select "label", text: "Named Lists", count: 0
    assert_select "input[name^=?]", "kanban_list_ids", count: 0
    assert_select "input[name=?]", "named_list_ids[]", count: 0
  end

  test "persisted idea edit form still renders list and board placement controls" do
    board = @user.kanban_boards.create!(name: "Validation")
    @user.lists.create!(name: "Queued", kind: :kanban, kanban_board: board)
    @user.lists.create!(name: "Launch Candidates", kind: :named)

    get edit_idea_url(@idea)

    assert_response :success
    assert_select "label", text: "Kanban Boards"
    assert_select "label", text: "Named Lists"
    assert_select "input[name^=?]", "kanban_list_ids"
    assert_select "input[name=?]", "named_list_ids[]"
  end

  test "should create idea" do
    assert_difference("Idea.count") do
      post ideas_url, params: { idea: { title: "New Idea" } }
    end

    assert_redirected_to uncompleted_ideas_url(idea_draft_saved: 1)
  end

  test "create ignores list and board placement params" do
    board = @user.kanban_boards.create!(name: "Validation")
    kanban_list = @user.lists.create!(name: "Queued", kind: :kanban, kanban_board: board)
    named_list = @user.lists.create!(name: "Launch Candidates", kind: :named)

    assert_difference("Idea.count", 1) do
      assert_no_difference("IdeaList.count") do
        post ideas_url, params: {
          idea: { title: "New Idea" },
          kanban_list_ids: { board.id => kanban_list.id },
          named_list_ids: [named_list.id]
        }
      end
    end
  end

  test "promoting a draft ignores list and board placement params" do
    draft = @user.ideas.create!(title: "Draft", state: :idea_new, draft: true)
    board = @user.kanban_boards.create!(name: "Validation")
    kanban_list = @user.lists.create!(name: "Queued", kind: :kanban, kanban_board: board)
    named_list = @user.lists.create!(name: "Launch Candidates", kind: :named)

    assert_no_difference("IdeaList.count") do
      patch idea_url(draft), params: {
        idea: { title: "Promoted" },
        kanban_list_ids: { board.id => kanban_list.id },
        named_list_ids: [named_list.id]
      }
    end

    draft.reload
    refute draft.draft?
    assert_empty draft.lists
  end

  test "should show idea" do
    get idea_url(@idea)
    assert_response :success
  end

  test "show renders inline agent recommendation diff previews" do
    @idea.update!(description: "Original line\nKeep line")
    recommendation = @user.agent_recommendations.create!(
      target: @idea,
      action: "update_idea",
      risk_level: "medium",
      reasoning: "Tighten the idea copy",
      payload: {
        "idea_id" => @idea.id,
        "title" => "Sharper Test Idea",
        "description" => "Proposed line\nKeep line"
      }
    )

    get idea_url(@idea)

    assert_response :success
    assert_select "#agent-suggestions"
    assert_select "[data-agent-recommendation-id=?]", recommendation.id.to_s
    assert_select "form[action=?]", settings_local_agent_recommendation_approve_path(recommendation)
    assert_select "form[action=?]", settings_local_agent_recommendation_dismiss_path(recommendation)
    assert_select ".agent-diff__line--delete code", text: "Original line"
    assert_select ".agent-diff__line--insert code", text: "Proposed line"
  end

  test "show renders collapsed agent addition and file previews" do
    recommendation = @user.agent_recommendations.create!(
      target: @idea,
      action: "create_note",
      risk_level: "low",
      reasoning: "Capture a research note",
      payload: {
        "idea_id" => @idea.id,
        "body" => "Investigate channel pricing",
        "files" => [
          { "path" => "research/channel.md", "content" => "Pricing notes" }
        ]
      }
    )

    get idea_url(@idea)

    assert_response :success
    assert_select "[data-agent-recommendation-id=?]", recommendation.id.to_s
    assert_select ".agent-addition summary strong", text: "New note"
    assert_select ".agent-addition--file summary strong", text: "research/channel.md"
    assert_match "Pricing notes", response.body
  end

  test "show hides agent access while idea work tokens are disabled" do
    @user.update_idea_work_token_settings("enabled" => "0")

    get idea_url(@idea)

    assert_response :success
    assert_select ".idea-agent-access", 0
  end

  test "show renders compact agent access while idea work tokens are enabled" do
    @user.update_idea_work_token_settings("enabled" => "1")
    IdeaAgentToken.generate(idea: @idea, name: "Existing")

    get idea_url(@idea)

    assert_response :success
    assert_select ".idea-agent-access", 1
    assert_select ".idea-agent-access__usage", 0
    assert_select ".idea-agent-access__row", 1
  end

  test "should get edit" do
    get edit_idea_url(@idea)
    assert_response :success
  end

  test "persisted idea edit form enables encrypted edit persistence with idea scoped storage" do
    get edit_idea_url(@idea)

    assert_response :success
    assert_select "form[data-controller~=?]", "idea-draft-persist", count: 1 do
      assert_select "[data-idea-draft-persist-storage-key-value=?]", "idea-edit-draft:v1:user-#{@user.id}:idea-#{@idea.id}", count: 1
      assert_select "[data-idea-draft-persist-prompt-with-existing-content-value=?]", "true", count: 1
      assert_select "button[data-action*=?]", "idea-draft-persist#restore", count: 1
    end
  end

  test "edit form renders collapsible OCR sidebar for extracted attachment parts" do
    @idea.attachments.attach(
      io: StringIO.new("scanned data"),
      filename: "scan.txt",
      content_type: "text/plain"
    )
    attachment = @idea.attachments.last
    attachment.update!(ocr_status: "complete", ocr_text: "Widget bracket\nM4 bolt", ocr_metadata: { "parts" => ["Widget bracket", "M4 bolt"] })

    get edit_idea_url(@idea)

    assert_response :success
    assert_select ".form-sidebar .idea-form-ocr-sidebar", 1
    assert_select ".idea-form-ocr-sidebar details[open]", 1
    assert_select ".idea-form-ocr-sidebar li span", text: "Widget bracket"
    assert_select ".idea-form-ocr-sidebar li span", text: "M4 bolt"
  end

  test "edit form separates image and document attachments" do
    @idea.attachments.attach(
      io: StringIO.new("image data"),
      filename: "mockup.png",
      content_type: "image/png"
    )
    @idea.attachments.attach(
      io: StringIO.new("document data"),
      filename: "brief.pdf",
      content_type: "application/pdf"
    )

    get edit_idea_url(@idea)

    assert_response :success
    assert_select ".current-attachments__section--images [data-attachment-kind=?]", "image", 1
    assert_select ".current-attachments__section--images img.current-attachments__thumb", 1
    assert_select ".current-attachments__section--documents [data-attachment-kind=?]", "document", 1
    assert_select ".current-attachments__section--documents [data-filename=?]", "brief.pdf", 1
  end

  test "show media tab separates images and documents" do
    @idea.attachments.attach(
      io: StringIO.new("image data"),
      filename: "mockup.png",
      content_type: "image/png"
    )
    @idea.attachments.attach(
      io: StringIO.new("document data"),
      filename: "brief.pdf",
      content_type: "application/pdf"
    )

    get idea_url(@idea)

    assert_response :success
    assert_select ".media-section__group--images img.attachment-thumbnail", 1
    assert_select ".media-section__group--documents .attachment-file", 1
    assert_select ".media-section__group--documents .attachment-name", text: "brief.pdf"
  end

  test "should update idea" do
    patch idea_url(@idea), params: { idea: { title: "Updated Title" } }
    assert_redirected_to idea_url(@idea, idea_edit_saved: 1)
    
    @idea.reload
    assert_equal "Updated Title", @idea.title
  end

  test "adds idea to named list through context menu endpoint" do
    named_list = @user.lists.create!(name: "Launch Candidates", kind: :named)

    assert_difference -> { named_list.idea_lists.count }, 1 do
      post "/ideas/#{@idea.id}/add_to_list", params: { list_id: named_list.id }, as: :json
    end

    assert_response :success
    payload = JSON.parse(response.body)
    assert_equal named_list.id, payload.dig("list", "id")
    assert_equal "named", payload.dig("list", "kind")
  end

  test "adds idea to one kanban column on the selected board through context menu endpoint" do
    board = @user.kanban_boards.create!(name: "Validation")
    queued = @user.lists.create!(name: "Queued", kind: :kanban, kanban_board: board)
    active = @user.lists.create!(name: "Active", kind: :kanban, kanban_board: board)
    @idea.idea_lists.create!(list: queued)

    assert_no_difference -> { @idea.idea_lists.joins(:list).where(lists: { kind: "kanban", kanban_board_id: board.id }).count } do
      post "/ideas/#{@idea.id}/add_to_list", params: { list_id: active.id }, as: :json
    end

    assert_response :success
    @idea.reload
    assert_equal active, @idea.idea_lists.joins(:list).find_by(lists: { kanban_board_id: board.id }).list
    refute @idea.lists.exists?(queued.id)
  end

  test "should destroy idea" do
    assert_difference("Idea.count", -1) do
      delete idea_url(@idea)
    end

    assert_redirected_to ideas_url
  end

  # Cool-off period validation tests (Requirement 3.4)
  test "should not allow editing idea during cool-off period" do
    @idea.update!(state: :incubating, cool_off_until: 1.day.from_now)
    
    get edit_idea_url(@idea)
    assert_redirected_to idea_url(@idea)
    assert_match /cool-off period/, flash[:alert]
  end

  test "should not allow updating idea during cool-off period" do
    @idea.update!(state: :incubating, cool_off_until: 1.day.from_now)
    
    patch idea_url(@idea), params: { idea: { title: "Should Not Update" } }
    assert_redirected_to idea_url(@idea)
    assert_match /cool-off period/, flash[:alert]
    
    @idea.reload
    assert_not_equal "Should Not Update", @idea.title
  end

  test "should allow editing idea after cool-off period expires" do
    @idea.update!(state: :incubating, cool_off_until: 1.day.ago)
    
    get edit_idea_url(@idea)
    assert_response :success
  end

  test "should allow editing idea not in cool-off period" do
    @idea.update!(state: :triage, cool_off_until: nil)
    
    get edit_idea_url(@idea)
    assert_response :success
  end

  # Archive / Restore tests
  test "should archive idea" do
    post archive_idea_url(@idea)
    assert_redirected_to ideas_url

    @idea.reload
    assert @idea.archived?
    assert @idea.discarded_at.present?
  end

  test "should restore archived idea" do
    @idea.update!(discarded_at: Time.current)

    post restore_idea_url(@idea)
    assert_redirected_to idea_url(@idea)

    @idea.reload
    refute @idea.archived?
    assert_nil @idea.discarded_at
  end

  test "should show archived ideas page" do
    @idea.update!(discarded_at: Time.current)

    get archived_ideas_url
    assert_response :success
  end

  test "archived ideas are excluded from index by default" do
    @idea.update!(discarded_at: Time.current)

    get ideas_url
    assert_response :success
    # The archived idea should not appear in the response body
    assert_no_match @idea.title, response.body
  end

  # Search tests
  test "search endpoint returns JSON results" do
    get search_ideas_url(q: @idea.title)
    assert_response :success

    json = JSON.parse(response.body)
    assert json["results"].is_a?(Array)
  end

  test "search finds ideas by title" do
    get search_ideas_url(q: "Test Idea")
    assert_response :success

    json = JSON.parse(response.body)
    assert json["results"].any? { |r| r["id"] == @idea.id }
  end

  test "search returns empty for blank query" do
    get search_ideas_url(q: "")
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal [], json["results"]
  end

  # Enrichment tests
  test "enrich action enqueues job" do
    assert_enqueued_with(job: IdeaEnrichmentJob) do
      post enrich_idea_url(@idea)
    end

    assert_redirected_to idea_url(@idea)
  end

  test "enrichment_status returns JSON" do
    get enrichment_status_idea_url(@idea)
    assert_response :success

    json = JSON.parse(response.body)
    assert_equal @idea.id, json["idea_id"]
    assert json.key?("enriched")
  end
end
