# Idea Agent Document Access Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an idea owner mint scoped tokens for external agents, LLMs, and harnesses so they can read and keep updating one idea's working document while every accepted change lands in normal version history.

**Architecture:** Add an `IdeaAgentToken` model scoped to one `Idea`, storing only SHA-256 token digests. Add owner-facing nested routes to create/revoke tokens, plus a JSON API controller that authenticates a bearer token, exposes the current document, and replaces or appends to `Idea#description` inside a transaction that creates a `Version`.

**Tech Stack:** Rails 8, Active Record, Action Text, Minitest integration/model tests, existing version history.

---

### Task 1: Token Model And Persistence

**Files:**
- Create: `db/migrate/20260513090000_create_idea_agent_tokens.rb`
- Create: `app/models/idea_agent_token.rb`
- Modify: `app/models/idea.rb`
- Test: `test/models/idea_agent_token_test.rb`

- [ ] **Step 1: Write the failing test**

```ruby
require "test_helper"

class IdeaAgentTokenTest < ActiveSupport::TestCase
  setup do
    @idea = ideas(:one)
  end

  test "generate stores only a digest and authenticates active unexpired tokens" do
    token = IdeaAgentToken.generate(idea: @idea, name: "Spec Bot")

    assert token.persisted?
    assert token.raw_token.present?
    assert_not_equal token.raw_token, token.token_digest
    assert_equal token, IdeaAgentToken.authenticate(token.raw_token)
    assert token.reload.last_used_at.present?
  end

  test "authenticate rejects inactive and expired tokens" do
    inactive = IdeaAgentToken.generate(idea: @idea, name: "Inactive")
    inactive.update!(active: false)

    expired = IdeaAgentToken.generate(idea: @idea, name: "Expired", expires_at: 1.minute.ago)

    assert_nil IdeaAgentToken.authenticate(inactive.raw_token)
    assert_nil IdeaAgentToken.authenticate(expired.raw_token)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/idea_agent_token_test.rb`

Expected: fail because `IdeaAgentToken` is not defined and the table does not exist.

- [ ] **Step 3: Add the minimal model and migration**

```ruby
class CreateIdeaAgentTokens < ActiveRecord::Migration[8.0]
  def change
    create_table :idea_agent_tokens do |t|
      t.references :idea, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.string :name, null: false
      t.datetime :last_used_at
      t.datetime :expires_at
      t.boolean :active, null: false, default: true
      t.timestamps
    end

    add_index :idea_agent_tokens, :token_digest, unique: true
    add_index :idea_agent_tokens, [:idea_id, :active]
  end
end
```

```ruby
class IdeaAgentToken < ApplicationRecord
  belongs_to :idea

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> { where(active: true).where("expires_at IS NULL OR expires_at > ?", Time.current) }

  attr_accessor :raw_token

  def self.generate(idea:, name:, expires_at: nil)
    raw_token = SecureRandom.hex(32)
    token = create!(
      idea: idea,
      name: name,
      token_digest: Digest::SHA256.hexdigest(raw_token),
      expires_at: expires_at
    )
    token.raw_token = raw_token
    token
  end

  def self.authenticate(raw_token)
    return nil if raw_token.blank?

    token = active.find_by(token_digest: Digest::SHA256.hexdigest(raw_token))
    token&.tap { |record| record.update_column(:last_used_at, Time.current) }
  end
end
```

Add to `Idea`:

```ruby
has_many :idea_agent_tokens, dependent: :destroy
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/idea_agent_token_test.rb`

Expected: pass.

### Task 2: Agent Document API

**Files:**
- Create: `app/controllers/api/v1/idea_documents_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/controllers/api/v1/idea_documents_controller_test.rb`

- [ ] **Step 1: Write the failing API tests**

```ruby
require "test_helper"

class Api::V1::IdeaDocumentsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @idea = ideas(:one)
    @idea.description = "Initial spec"
    @idea.save!
    @version = @idea.create_version("Initial version")
    @token = IdeaAgentToken.generate(idea: @idea, name: "Spec Bot")
    @headers = { "Authorization" => "Bearer #{@token.raw_token}" }
  end

  test "shows the idea document for a valid idea token" do
    get api_v1_idea_document_url(@idea), headers: @headers

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal @idea.id, json["idea_id"]
    assert_equal "Mobile App for Local Farmers", json["title"]
    assert_equal "Initial spec", json["description"]
    assert_equal @version.id, json["latest_version_id"]
  end

  test "updates the idea document and records version history" do
    assert_difference -> { @idea.versions.count }, 1 do
      patch api_v1_idea_document_url(@idea),
            params: { description: "Revised spec", commit_message: "Tighten acceptance criteria" }.to_json,
            headers: @headers.merge("Content-Type" => "application/json")
    end

    assert_response :success
    @idea.reload
    assert_equal "Revised spec", @idea.description.to_plain_text
    assert_equal "Spec Bot: Tighten acceptance criteria", @idea.latest_version.commit_message
  end

  test "rejects stale base version updates" do
    @idea.description = "Human edit"
    @idea.save!
    current = @idea.create_version("Human edit")

    patch api_v1_idea_document_url(@idea),
          params: { description: "Stale edit", base_version_id: @version.id }.to_json,
          headers: @headers.merge("Content-Type" => "application/json")

    assert_response :conflict
    assert_equal current.id, JSON.parse(response.body)["latest_version_id"]
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/api/v1/idea_documents_controller_test.rb`

Expected: fail because route/controller do not exist.

- [ ] **Step 3: Implement the minimal API**

Add `resource :document, only: [:show, :update], controller: :idea_documents` under `api/v1/resources :ideas`.

Controller behavior:
- Authenticate `Authorization: Bearer <token>` with `IdeaAgentToken.authenticate`.
- Ensure the token's idea id matches `params[:idea_id]`; return `404` for mismatches.
- `show` returns `idea_id`, `title`, `description`, `updated_at`, `latest_version_id`.
- `update` accepts one of `description`, `content`, or `append`.
- Optional `base_version_id` returns `409` when it does not match the current latest version id.
- Save the document and call `idea.create_version("#{token.name}: #{message}")` only when content changed.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/api/v1/idea_documents_controller_test.rb`

Expected: pass.

### Task 3: Owner UI For Invites

**Files:**
- Create: `app/controllers/idea_agent_tokens_controller.rb`
- Create: `app/views/ideas/_agent_access.html.erb`
- Modify: `app/views/ideas/show.html.erb`
- Modify: `app/assets/stylesheets/idea_detail.css`
- Modify: `config/routes.rb`
- Test: `test/controllers/idea_agent_tokens_controller_test.rb`

- [ ] **Step 1: Write the failing controller tests**

```ruby
require "test_helper"

class IdeaAgentTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @idea = ideas(:one)
  end

  test "creates an idea token and flashes the raw token once" do
    assert_difference -> { @idea.idea_agent_tokens.count }, 1 do
      post idea_agent_tokens_url(@idea), params: { idea_agent_token: { name: "Harness" } }
    end

    assert_redirected_to idea_url(@idea)
    assert flash[:idea_agent_token].present?
  end

  test "destroys an idea token" do
    token = IdeaAgentToken.generate(idea: @idea, name: "Harness")

    assert_difference -> { @idea.idea_agent_tokens.count }, -1 do
      delete idea_agent_token_url(@idea, token)
    end

    assert_redirected_to idea_url(@idea)
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/idea_agent_tokens_controller_test.rb`

Expected: fail because routes/controller do not exist.

- [ ] **Step 3: Implement UI and owner routes**

Add nested `resources :agent_tokens, only: [:create, :destroy], controller: :idea_agent_tokens` under `resources :ideas`.

Add a compact `Agent Access` panel on the idea detail page that:
- Displays the one-time raw token from `flash[:idea_agent_token]`.
- Creates tokens with a required name.
- Lists active tokens with created/last-used metadata.
- Revokes tokens with a delete button.
- Shows curl examples for GET/PATCH against `/api/v1/ideas/:idea_id/document` using the bearer token.

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/controllers/idea_agent_tokens_controller_test.rb`

Expected: pass.

### Task 4: Verification And Release Hygiene

**Files:**
- Modify: `db/schema.rb`
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Run migration**

Run: `bin/rails db:migrate`

Expected: `db/schema.rb` includes `idea_agent_tokens`.

- [ ] **Step 2: Run focused tests**

Run: `bin/rails test test/models/idea_agent_token_test.rb test/controllers/api/v1/idea_documents_controller_test.rb test/controllers/idea_agent_tokens_controller_test.rb`

Expected: all pass.

- [ ] **Step 3: Run broader nearby regression tests**

Run: `bin/rails test test/models/idea_test.rb test/models/version_test.rb test/controllers/ideas_controller_test.rb`

Expected: all pass or existing unrelated failures are documented.

- [ ] **Step 4: Update changelog**

Add an `Unreleased` entry noting scoped idea document tokens for agent/LLM/harness collaboration and history-tracked document API updates.

- [ ] **Step 5: Commit and push**

Run:

```bash
git add app db test config docs CHANGELOG.md
git commit -m "feat: add scoped idea document agent tokens"
git push
```

Expected: commit succeeds and pushes to the configured `origin`.
