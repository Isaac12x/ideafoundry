# Napkin Calculations Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an optional spreadsheet-style "Back-of-the-napkin" section to ideas (create/edit form + read-only show), with formulas, range selection, lazy-loaded JS engine, server-side eval for show.

**Architecture:** New `napkin_calculations` JSON column on `ideas`. Stimulus controller (`napkin_controller.js`) drives the editable grid using a lazy-loaded `hot-formula-parser`. The show page renders cells server-side using the `dentaku` gem (no JS). Helpers shared between server-render and client-render keep formatting consistent.

**Tech Stack:** Rails 8, SQLite, Stimulus, esbuild, `dentaku` (Ruby), `hot-formula-parser` (JS).

**Spec:** `docs/superpowers/specs/2026-04-30-napkin-calculations-design.md`.

**File Structure (new + modified):**

```
db/migrate/<ts>_add_napkin_calculations_to_ideas.rb        NEW
db/schema.rb                                               MODIFIED
Gemfile / Gemfile.lock                                     MODIFIED (add dentaku)
package.json / yarn.lock                                   MODIFIED (add hot-formula-parser)

app/models/idea.rb                                         MODIFIED (serialize, helpers, validation)
app/controllers/ideas_controller.rb                        MODIFIED (permit, parse JSON)
app/helpers/napkin_helper.rb                               NEW (server-side eval + format)

app/views/ideas/_form.html.erb                             MODIFIED (render _napkin)
app/views/ideas/_napkin.html.erb                           NEW (form panel, collapsible)
app/views/ideas/show.html.erb                              MODIFIED (render _napkin_readonly)
app/views/ideas/_napkin_readonly.html.erb                  NEW (show-page, server-rendered)

app/javascript/controllers/napkin_controller.js            NEW (Stimulus, grid editor)
app/javascript/controllers/index.js                        MODIFIED (register controller)

app/assets/stylesheets/napkin.css                          NEW (grid styles)
app/assets/stylesheets/application.css                     MODIFIED (or import napkin.css)

test/models/idea_napkin_test.rb                            NEW
test/helpers/napkin_helper_test.rb                         NEW
test/controllers/ideas_controller_napkin_test.rb           NEW
test/system/napkin_calculations_test.rb                    NEW
```

---

## Task 1: Add `dentaku` gem and `hot-formula-parser` package

**Files:**
- Modify: `Gemfile`
- Modify: `package.json`

- [ ] **Step 1: Add `dentaku` to Gemfile**

In `Gemfile`, add a new line at the end of the application gems group:

```ruby
gem "dentaku", "~> 3.5"
```

- [ ] **Step 2: Install gem**

Run: `bundle install`
Expected: `dentaku 3.x.x` resolved and installed; `Gemfile.lock` updated.

- [ ] **Step 3: Verify gem loads**

Run: `bin/rails runner 'puts Dentaku::Calculator.new.evaluate("2 + 2")'`
Expected: `4`

- [ ] **Step 4: Add `hot-formula-parser` to package.json**

Run: `yarn add hot-formula-parser@^4.0.0`
Expected: `package.json` shows `"hot-formula-parser": "^4.0.0"` under dependencies; `yarn.lock` updated.

- [ ] **Step 5: Verify build still works**

Run: `yarn build`
Expected: build completes without errors.

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock package.json yarn.lock
git commit -m "deps: add dentaku and hot-formula-parser for napkin calculations"
```

---

## Task 2: Migration — add `napkin_calculations` JSON column

**Files:**
- Create: `db/migrate/20260430120000_add_napkin_calculations_to_ideas.rb`
- Modify: `db/schema.rb` (auto-generated)

- [ ] **Step 1: Generate migration file**

Run: `bin/rails generate migration AddNapkinCalculationsToIdeas napkin_calculations:json`
Expected: file `db/migrate/<timestamp>_add_napkin_calculations_to_ideas.rb` created.

- [ ] **Step 2: Verify migration content**

Open the generated file. It should look like:

```ruby
class AddNapkinCalculationsToIdeas < ActiveRecord::Migration[8.0]
  def change
    add_column :ideas, :napkin_calculations, :json
  end
end
```

If different, replace its contents with the above.

- [ ] **Step 3: Run migration**

Run: `bin/rails db:migrate`
Expected: migration runs cleanly; `db/schema.rb` shows `t.json "napkin_calculations"` on the ideas table.

- [ ] **Step 4: Verify column in schema**

Run: `grep -n napkin_calculations db/schema.rb`
Expected: one matching line under the `ideas` table block.

- [ ] **Step 5: Commit**

```bash
git add db/migrate/*napkin* db/schema.rb
git commit -m "db: add napkin_calculations json column to ideas"
```

---

## Task 3: Idea model — serialize, helpers, size validation (TDD)

**Files:**
- Modify: `app/models/idea.rb`
- Create: `test/models/idea_napkin_test.rb`

- [ ] **Step 1: Write failing test**

Create `test/models/idea_napkin_test.rb`:

```ruby
require "test_helper"

class IdeaNapkinTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "napkin@test.example", name: "Napkin User")
    @idea = @user.ideas.create!(title: "T", state: :idea_new, attempt_count: 0)
  end

  test "napkin_present? false when nil" do
    assert_nil @idea.napkin_calculations
    assert_not @idea.napkin_present?
  end

  test "napkin_present? false when cells empty" do
    @idea.update!(napkin_calculations: { "rows" => 10, "cols" => 5, "cells" => {} })
    assert_not @idea.napkin_present?
  end

  test "napkin_present? true when cells populated" do
    @idea.update!(napkin_calculations: {
      "rows" => 10, "cols" => 5,
      "cells" => { "A1" => { "raw" => "Users", "fmt" => nil } }
    })
    assert @idea.napkin_present?
  end

  test "napkin_cell returns cell hash or nil" do
    @idea.update!(napkin_calculations: {
      "rows" => 10, "cols" => 5,
      "cells" => { "A1" => { "raw" => "1000", "fmt" => "number:0" } }
    })
    assert_equal({ "raw" => "1000", "fmt" => "number:0" }, @idea.napkin_cell("A1"))
    assert_nil @idea.napkin_cell("Z99")
  end

  test "rejects payload with too many cells" do
    cells = (1..2001).each_with_object({}) { |i, h| h["A#{i}"] = { "raw" => "x", "fmt" => nil } }
    @idea.napkin_calculations = { "rows" => 100, "cols" => 26, "cells" => cells }
    assert_not @idea.valid?
    assert_includes @idea.errors[:napkin_calculations].to_s, "too many cells"
  end

  test "rejects payload with rows > 100" do
    @idea.napkin_calculations = { "rows" => 101, "cols" => 5, "cells" => {} }
    assert_not @idea.valid?
    assert_includes @idea.errors[:napkin_calculations].to_s, "rows"
  end

  test "rejects payload with cols > 26" do
    @idea.napkin_calculations = { "rows" => 10, "cols" => 27, "cells" => {} }
    assert_not @idea.valid?
    assert_includes @idea.errors[:napkin_calculations].to_s, "cols"
  end

  test "JSON round-trip preserves structure" do
    payload = {
      "rows" => 10, "cols" => 5,
      "cells" => {
        "A1" => { "raw" => "Users", "fmt" => nil },
        "B1" => { "raw" => "1000", "fmt" => "number:0" },
        "B3" => { "raw" => "=B1*2", "fmt" => "currency:USD:0" }
      }
    }
    @idea.update!(napkin_calculations: payload)
    @idea.reload
    assert_equal payload, @idea.napkin_calculations
  end
end
```

- [ ] **Step 2: Run test to verify failures**

Run: `bin/rails test test/models/idea_napkin_test.rb`
Expected: all tests fail (no `napkin_present?`, no validation, etc.).

- [ ] **Step 3: Add serialize, helpers, and validation to Idea model**

In `app/models/idea.rb`, find the `# JSON serialization` line and add a second serialize directive right below it:

```ruby
  # JSON serialization
  serialize :metadata, coder: JSON
  serialize :napkin_calculations, coder: JSON
```

Then add a new validation in the validations block (right after the existing `validate :template_required_fields_present` line):

```ruby
  validate :napkin_calculations_within_limits
```

Add three public helper methods near the other helpers (after `enrichment_data`/`enriched?`, before `private`):

```ruby
  # Napkin calculations helpers
  def napkin_present?
    napkin_calculations.is_a?(Hash) && napkin_calculations["cells"].is_a?(Hash) && napkin_calculations["cells"].any?
  end

  def napkin_cell(ref)
    return nil unless napkin_calculations.is_a?(Hash)
    napkin_calculations.dig("cells", ref)
  end
```

Add the validation method in the `private` section (anywhere among the existing private methods):

```ruby
  def napkin_calculations_within_limits
    return if napkin_calculations.nil?
    unless napkin_calculations.is_a?(Hash)
      errors.add(:napkin_calculations, "must be a hash")
      return
    end

    rows = napkin_calculations["rows"].to_i
    cols = napkin_calculations["cols"].to_i
    cells = napkin_calculations["cells"]

    errors.add(:napkin_calculations, "rows must be 1..100") if rows < 1 || rows > 100
    errors.add(:napkin_calculations, "cols must be 1..26") if cols < 1 || cols > 26

    if cells.is_a?(Hash) && cells.size > 2000
      errors.add(:napkin_calculations, "too many cells (max 2000)")
    end
  end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/idea_napkin_test.rb`
Expected: all 7 tests pass.

- [ ] **Step 5: Run full model test suite to confirm no regression**

Run: `bin/rails test test/models`
Expected: green.

- [ ] **Step 6: Commit**

```bash
git add app/models/idea.rb test/models/idea_napkin_test.rb
git commit -m "models: napkin_calculations on Idea (serialize, helpers, limits)"
```

---

## Task 4: Controller — permit and parse JSON param (TDD)

**Files:**
- Modify: `app/controllers/ideas_controller.rb`
- Create: `test/controllers/ideas_controller_napkin_test.rb`

- [ ] **Step 1: Write failing test**

Create `test/controllers/ideas_controller_napkin_test.rb`:

```ruby
require "test_helper"

class IdeasControllerNapkinTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.first || User.create!(email: "napkin-ctl@test.example", name: "Napkin Ctl")
    @idea = @user.ideas.create!(title: "T", state: :idea_new, attempt_count: 0)
  end

  test "update accepts napkin_calculations JSON string and persists hash" do
    payload = {
      rows: 10, cols: 5,
      cells: {
        "A1" => { raw: "Users", fmt: nil },
        "B1" => { raw: "1000", fmt: "number:0" }
      }
    }
    patch idea_path(@idea), params: {
      idea: { title: "T2", state: "idea_new", napkin_calculations: payload.to_json }
    }
    assert_response :redirect
    @idea.reload
    assert_equal 10, @idea.napkin_calculations["rows"]
    assert_equal "Users", @idea.napkin_calculations["cells"]["A1"]["raw"]
  end

  test "update with blank napkin_calculations stores nil" do
    @idea.update!(napkin_calculations: { "rows" => 10, "cols" => 5, "cells" => { "A1" => { "raw" => "x", "fmt" => nil } } })
    patch idea_path(@idea), params: {
      idea: { title: "T", state: "idea_new", napkin_calculations: "" }
    }
    @idea.reload
    assert_nil @idea.napkin_calculations
  end

  test "update with invalid JSON ignores the param (does not crash)" do
    patch idea_path(@idea), params: {
      idea: { title: "T3", state: "idea_new", napkin_calculations: "not json{" }
    }
    @idea.reload
    assert_nil @idea.napkin_calculations
    assert_equal "T3", @idea.title
  end
end
```

- [ ] **Step 2: Run test to verify failure**

Run: `bin/rails test test/controllers/ideas_controller_napkin_test.rb`
Expected: failures (param not permitted / not parsed).

- [ ] **Step 3: Update controller — permit + parse**

In `app/controllers/ideas_controller.rb`, modify the `idea_params` method (around line 274) to add `:napkin_calculations` to the permit list and parse the JSON string into a Hash:

```ruby
  def idea_params
    permitted = params.require(:idea).permit(
      :title, :state, :template_id,
      :trl, :difficulty, :opportunity, :timing,
      :difficulty_explanation, :opportunity_explanation, :timing_explanation,
      :description,
      :hero_image,
      :napkin_calculations,
      attachments: [],
      topology_ids: [],
      metadata: {}
    )
    permitted[:napkin_calculations] = parse_napkin_param(permitted[:napkin_calculations]) if permitted.key?(:napkin_calculations)
    permitted
  end

  def parse_napkin_param(raw)
    return nil if raw.blank?
    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end
```

- [ ] **Step 4: Run controller test to verify pass**

Run: `bin/rails test test/controllers/ideas_controller_napkin_test.rb`
Expected: all 3 tests pass.

- [ ] **Step 5: Run full controller test suite**

Run: `bin/rails test test/controllers`
Expected: green (no regressions in existing ideas tests).

- [ ] **Step 6: Commit**

```bash
git add app/controllers/ideas_controller.rb test/controllers/ideas_controller_napkin_test.rb
git commit -m "controllers: permit and parse idea[napkin_calculations] JSON"
```

---

## Task 5: NapkinHelper — server-side eval + cell formatter (TDD)

**Files:**
- Create: `app/helpers/napkin_helper.rb`
- Create: `test/helpers/napkin_helper_test.rb`

- [ ] **Step 1: Write failing tests**

Create `test/helpers/napkin_helper_test.rb`:

```ruby
require "test_helper"

class NapkinHelperTest < ActionView::TestCase
  include NapkinHelper

  def data(cells, rows: 10, cols: 5)
    { "rows" => rows, "cols" => cols, "cells" => cells }
  end

  test "evaluate plain numbers and text" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "Users", "fmt" => nil },
      "B1" => { "raw" => "1000",  "fmt" => nil }
    }))
    assert_equal "Users", result["A1"][:display]
    assert_equal "1000",  result["B1"][:display]
    assert_nil result["A1"][:error]
  end

  test "evaluate basic arithmetic formula" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "10",     "fmt" => nil },
      "B1" => { "raw" => "20",     "fmt" => nil },
      "C1" => { "raw" => "=A1+B1", "fmt" => nil }
    }))
    assert_equal "30", result["C1"][:display]
  end

  test "evaluate SUM range" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "1",      "fmt" => nil },
      "A2" => { "raw" => "2",      "fmt" => nil },
      "A3" => { "raw" => "3",      "fmt" => nil },
      "B1" => { "raw" => "=SUM(A1:A3)", "fmt" => nil }
    }))
    assert_equal "6", result["B1"][:display]
  end

  test "evaluate IF and ROUND" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "5", "fmt" => nil },
      "B1" => { "raw" => "=IF(A1>3, ROUND(A1*1.111, 2), 0)", "fmt" => nil }
    }))
    assert_equal "5.56", result["B1"][:display]
  end

  test "format_napkin_cell — currency" do
    assert_equal "$1,500.00", format_napkin_cell("1500", "currency:USD:2", 1500.0)
  end

  test "format_napkin_cell — percent" do
    assert_equal "75.0%", format_napkin_cell("0.75", "percent:1", 0.75)
  end

  test "format_napkin_cell — number with decimals" do
    assert_equal "3.14", format_napkin_cell("3.14159", "number:2", 3.14159)
  end

  test "format_napkin_cell — bold-only fmt preserves number formatting" do
    assert_equal "1000", format_napkin_cell("1000", "bold", 1000)
  end

  test "format_napkin_cell — bold|currency stacks" do
    out = format_napkin_cell("100", "bold|currency:USD:0", 100)
    assert_equal "$100", out
  end

  test "evaluate handles bad formula with error" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "=NOTAFUNCTION()", "fmt" => nil }
    }))
    assert_equal "#ERR", result["A1"][:display]
    assert_not_nil result["A1"][:error]
  end

  test "evaluate handles cycle" do
    result = napkin_evaluate(data({
      "A1" => { "raw" => "=B1", "fmt" => nil },
      "B1" => { "raw" => "=A1", "fmt" => nil }
    }))
    assert_equal "#CYCLE", result["A1"][:display]
  end
end
```

- [ ] **Step 2: Run helper test to verify failures**

Run: `bin/rails test test/helpers/napkin_helper_test.rb`
Expected: failures (helper does not exist).

- [ ] **Step 3: Create helper**

Create `app/helpers/napkin_helper.rb`:

```ruby
module NapkinHelper
  # Returns { ref => { display: String, value: Numeric|String|nil, error: String|nil } }.
  def napkin_evaluate(data)
    return {} unless data.is_a?(Hash)
    cells = data["cells"] || {}
    calc = Dentaku::Calculator.new

    # Bind plain numeric/string cells.
    cells.each do |ref, cell|
      raw = cell["raw"].to_s
      next if raw.start_with?("=")
      val = numeric_cast(raw)
      calc.store(ref.downcase, val.nil? ? raw : val)
    end

    out = {}
    cells.each do |ref, cell|
      raw = cell["raw"].to_s
      fmt = cell["fmt"]

      if raw.start_with?("=")
        expr = napkin_translate_formula(raw[1..])
        begin
          value = calc.evaluate!(expr)
          out[ref] = { display: format_napkin_cell(raw, fmt, value), value: value, error: nil }
        rescue Dentaku::ArgumentError, ZeroDivisionError
          out[ref] = { display: "#ERR", value: nil, error: "argument" }
        rescue Dentaku::Exceptions::ParseError, Dentaku::Exceptions::TokenizerError, Dentaku::Exceptions::UnboundVariableError
          out[ref] = { display: "#ERR", value: nil, error: "parse" }
        rescue Dentaku::Exceptions::Error => e
          msg = e.message.to_s
          if msg.match?(/cycle|recursion|stack/i)
            out[ref] = { display: "#CYCLE", value: nil, error: "cycle" }
          else
            out[ref] = { display: "#ERR", value: nil, error: "eval" }
          end
        rescue SystemStackError
          out[ref] = { display: "#CYCLE", value: nil, error: "cycle" }
        end
      else
        value = numeric_cast(raw)
        out[ref] = { display: format_napkin_cell(raw, fmt, value || raw), value: value || raw, error: nil }
      end
    end
    out
  end

  # `value` is the resolved numeric/string for the cell (formula result OR raw cast).
  def format_napkin_cell(raw, fmt, value)
    parts = (fmt || "").split("|")
    bold = parts.delete("bold")
    style = parts.first

    rendered =
      if value.is_a?(Numeric)
        case style
        when /\Anumber:(\d+)\z/
          format("%.#{$1.to_i}f", value)
        when /\Acurrency:([A-Z]{3}):(\d+)\z/
          symbol = currency_symbol($1)
          "#{symbol}#{number_with_delimiter_and_precision(value, $2.to_i)}"
        when /\Apercent:(\d+)\z/
          "#{format("%.#{$1.to_i}f", value * 100.0)}%"
        else
          # Auto: integers without decimals, floats trimmed of trailing zeros.
          value.is_a?(Integer) ? value.to_s : trim_trailing_zeros(format("%.10f", value))
        end
      else
        raw
      end

    bold ? "<b>#{ERB::Util.html_escape(rendered)}</b>".html_safe : rendered
  end

  private

  def numeric_cast(s)
    return nil if s.nil? || s.empty?
    Float(s)
  rescue ArgumentError, TypeError
    nil
  end

  # Dentaku uses lowercase identifiers; Excel-style A1 → a1 works after store(downcase).
  def napkin_translate_formula(expr)
    expr.gsub(/\b([A-Z])(\d+)\b/) { "#{$1.downcase}#{$2}" }
  end

  def number_with_delimiter_and_precision(value, decimals)
    int, dec = format("%.#{decimals}f", value).split(".")
    int_with_commas = int.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    dec ? "#{int_with_commas}.#{dec}" : int_with_commas
  end

  def trim_trailing_zeros(s)
    return s unless s.include?(".")
    s.sub(/0+\z/, "").sub(/\.\z/, "")
  end

  def currency_symbol(code)
    { "USD" => "$", "EUR" => "€", "GBP" => "£", "JPY" => "¥" }.fetch(code, "#{code} ")
  end
end
```

- [ ] **Step 4: Run helper test to verify pass**

Run: `bin/rails test test/helpers/napkin_helper_test.rb`
Expected: all 11 tests pass.

> If `napkin_evaluate` SUM range test fails because Dentaku does not natively understand `A1:A3`, replace `napkin_translate_formula` so it expands ranges to comma-separated lists:
>
> ```ruby
>   def napkin_translate_formula(expr)
>     expanded = expr.gsub(/\b([A-Z])(\d+):([A-Z])(\d+)\b/) do
>       c1, r1, c2, r2 = $1, $2.to_i, $3, $4.to_i
>       refs = []
>       (c1..c2).each { |c| (r1..r2).each { |r| refs << "#{c.downcase}#{r}" } }
>       refs.join(",")
>     end
>     expanded.gsub(/\b([A-Z])(\d+)\b/) { "#{$1.downcase}#{$2}" }
>   end
> ```

Re-run the test until green.

- [ ] **Step 5: Commit**

```bash
git add app/helpers/napkin_helper.rb test/helpers/napkin_helper_test.rb
git commit -m "helpers: NapkinHelper — server-side dentaku eval + cell formatter"
```

---

## Task 6: Show-page partial `_napkin_readonly`

**Files:**
- Create: `app/views/ideas/_napkin_readonly.html.erb`
- Modify: `app/views/ideas/show.html.erb`

- [ ] **Step 1: Create the partial**

Create `app/views/ideas/_napkin_readonly.html.erb`:

```erb
<%# Renders idea.napkin_calculations as a static evaluated grid. %>
<%# Locals: idea %>
<% data = idea.napkin_calculations %>
<% next_render = (data.is_a?(Hash) && data["cells"].is_a?(Hash) && data["cells"].any?) %>
<% if next_render %>
  <% rows = (data["rows"] || 10).to_i %>
  <% cols = (data["cols"] || 5).to_i %>
  <% evaluated = napkin_evaluate(data) %>
  <div class="napkin-readonly">
    <table class="napkin-grid napkin-grid--readonly">
      <thead>
        <tr>
          <th class="napkin-corner"></th>
          <% cols.times do |c| %>
            <th class="napkin-col-header"><%= ("A".ord + c).chr %></th>
          <% end %>
        </tr>
      </thead>
      <tbody>
        <% rows.times do |r| %>
          <tr>
            <th class="napkin-row-header"><%= r + 1 %></th>
            <% cols.times do |c| %>
              <% ref = "#{("A".ord + c).chr}#{r + 1}" %>
              <% cell = evaluated[ref] %>
              <td class="napkin-cell <%= 'napkin-cell--error' if cell&.dig(:error) %>">
                <%= cell ? cell[:display] : "" %>
              </td>
            <% end %>
          </tr>
        <% end %>
      </tbody>
    </table>
  </div>
<% end %>
```

- [ ] **Step 2: Render the partial in `show.html.erb`**

Open `app/views/ideas/show.html.erb`. Find a sensible location in the main column (after the description / metadata block, before notes — search for an existing `<div class="idea-section">` block). Add this just before the notes section (or before the closing `</div>` of the main column):

```erb
<% if @idea.napkin_present? %>
  <div class="idea-section">
    <h3 class="idea-section-title">Back-of-the-napkin</h3>
    <%= render "napkin_readonly", idea: @idea %>
  </div>
<% end %>
```

(If you cannot identify a clear "main column", place it just before the closing tag of the show layout's main wrapper. The exact selector is a styling concern — Task 13 covers CSS.)

- [ ] **Step 3: Manually verify in dev**

Run: `bin/rails runner '
  u = User.first || User.create!(email: "x@e.com", name: "X")
  i = u.ideas.create!(title: "Napkin smoke", state: :idea_new, attempt_count: 0,
    napkin_calculations: {"rows"=>3,"cols"=>3,"cells"=>{
      "A1"=>{"raw"=>"Users","fmt"=>nil},
      "B1"=>{"raw"=>"1000","fmt"=>"number:0"},
      "A2"=>{"raw"=>"ARPU","fmt"=>nil},
      "B2"=>{"raw"=>"50","fmt"=>"currency:USD:2"},
      "A3"=>{"raw"=>"Revenue","fmt"=>"bold"},
      "B3"=>{"raw"=>"=B1*B2","fmt"=>"currency:USD:0"}
    }})
  puts "Idea ID: #{i.id}"
'`

Then start `bin/dev` and visit `/ideas/<that id>`. Expected: a 3×3 grid renders with Users/1000, ARPU/$50.00, Revenue/$50,000.

- [ ] **Step 4: Commit**

```bash
git add app/views/ideas/_napkin_readonly.html.erb app/views/ideas/show.html.erb
git commit -m "views: read-only napkin grid on show page"
```

---

## Task 7: Form partial `_napkin` skeleton (collapsed by default)

**Files:**
- Create: `app/views/ideas/_napkin.html.erb`
- Modify: `app/views/ideas/_form.html.erb`

- [ ] **Step 1: Create the form partial**

Create `app/views/ideas/_napkin.html.erb`:

```erb
<%# Locals: idea, form %>
<% data = idea.napkin_calculations || { "rows" => 10, "cols" => 5, "cells" => {} } %>
<% expanded = idea.napkin_present? %>
<div class="form-panel napkin-panel"
     data-controller="napkin"
     data-napkin-initial-value="<%= data.to_json %>"
     data-napkin-input-name-value="idea[napkin_calculations]"
     data-napkin-expanded-value="<%= expanded %>">

  <div class="napkin-header" data-action="click->napkin#toggle">
    <h3 class="form-panel-title">Back-of-the-napkin</h3>
    <button type="button" class="napkin-toggle-btn" data-napkin-target="toggleBtn" aria-expanded="<%= expanded %>">
      <svg class="napkin-chevron" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="6 9 12 15 18 9"/></svg>
    </button>
  </div>

  <div class="napkin-body <%= 'hidden' unless expanded %>" data-napkin-target="body">
    <div class="napkin-toolbar">
      <select class="napkin-fmt-select" data-napkin-target="fmtSelect" data-action="change->napkin#applyFormat">
        <option value="">Auto</option>
        <option value="number">Number</option>
        <option value="currency:USD">Currency (USD)</option>
        <option value="currency:EUR">Currency (EUR)</option>
        <option value="percent">Percent</option>
      </select>
      <label class="napkin-decimals">
        Decimals
        <input type="number" min="0" max="6" value="2" class="napkin-decimals-input" data-napkin-target="decimalsInput" data-action="change->napkin#applyFormat">
      </label>
      <button type="button" class="napkin-bold-btn" data-napkin-target="boldBtn" data-action="click->napkin#toggleBold"><b>B</b></button>
      <span class="napkin-spacer"></span>
      <button type="button" class="napkin-row-btn" data-action="click->napkin#addRow">+ Row</button>
      <button type="button" class="napkin-col-btn" data-action="click->napkin#addCol">+ Col</button>
    </div>

    <div class="napkin-formula-bar">
      <span class="napkin-formula-label" data-napkin-target="formulaRef">A1</span>
      <input type="text" class="napkin-formula-input" data-napkin-target="formulaBar" data-action="input->napkin#formulaBarEdit keydown->napkin#formulaBarKey">
    </div>

    <div class="napkin-grid-wrap">
      <div class="napkin-grid" data-napkin-target="grid"></div>
    </div>

    <div class="napkin-loading hidden" data-napkin-target="loading">Loading formula engine…</div>
  </div>

  <%= form.hidden_field :napkin_calculations, value: idea.napkin_calculations&.to_json, data: { napkin_target: "hiddenInput" } %>
</div>
```

- [ ] **Step 2: Render in form**

Open `app/views/ideas/_form.html.erb`. Find the comment `<!-- Custom Fields from Template (flat, sorted by position) -->` (around line 300). Add the napkin partial render immediately after the closing `<% end %>` of the custom-fields panel and before the `<!-- Hidden container ...` line:

```erb
      <!-- Back-of-the-napkin Calculations -->
      <%= render "napkin", idea: idea, form: form %>
```

- [ ] **Step 3: Verify form still renders**

Run: `bin/dev` (in another terminal if needed) and load `/ideas/new` (or `/ideas/<id>/edit`).
Expected: the form loads; a "Back-of-the-napkin" panel appears, collapsed; clicking the chevron does nothing yet (no JS controller).

- [ ] **Step 4: Commit**

```bash
git add app/views/ideas/_napkin.html.erb app/views/ideas/_form.html.erb
git commit -m "views: napkin form panel skeleton + hidden field wiring"
```

---

## Task 8: Stimulus controller — initial render & toggle (no eval yet)

**Files:**
- Create: `app/javascript/controllers/napkin_controller.js`
- Modify: `app/javascript/controllers/index.js`

- [ ] **Step 1: Create the controller**

Create `app/javascript/controllers/napkin_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

const COL_LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

export default class extends Controller {
  static targets = ["body", "grid", "toggleBtn", "fmtSelect", "decimalsInput", "boldBtn",
                    "hiddenInput", "formulaBar", "formulaRef", "loading"]
  static values  = { initial: String, inputName: String, expanded: Boolean }

  connect() {
    const init = this.initialValue ? JSON.parse(this.initialValue) : { rows: 10, cols: 5, cells: {} }
    this.state = {
      rows: init.rows || 10,
      cols: init.cols || 5,
      cells: new Map(Object.entries(init.cells || {})),
      selection: { anchor: "A1", focus: "A1" }
    }
    this.parser = null
    this.parserLoading = false

    this.renderGrid()
    this.syncHiddenInput()
    if (this.expandedValue) this.ensureParserLoaded()
  }

  toggle(e) {
    if (e && e.target.closest("input, select, button.napkin-toggle-btn") === null && e.currentTarget !== this.element.querySelector(".napkin-header")) return
    const isOpen = !this.bodyTarget.classList.contains("hidden")
    if (isOpen) {
      this.bodyTarget.classList.add("hidden")
      this.toggleBtnTarget.setAttribute("aria-expanded", "false")
    } else {
      this.bodyTarget.classList.remove("hidden")
      this.toggleBtnTarget.setAttribute("aria-expanded", "true")
      this.ensureParserLoaded()
    }
  }

  cellRef(c, r) { return `${COL_LETTERS[c]}${r + 1}` }
  parseRef(ref) {
    const m = /^([A-Z])(\d+)$/.exec(ref)
    return m ? { c: COL_LETTERS.indexOf(m[1]), r: parseInt(m[2], 10) - 1 } : null
  }

  renderGrid() {
    const { rows, cols, cells } = this.state
    const el = this.gridTarget
    let html = '<table class="napkin-grid-table"><thead><tr><th class="napkin-corner"></th>'
    for (let c = 0; c < cols; c++) html += `<th class="napkin-col-header">${COL_LETTERS[c]}</th>`
    html += "</tr></thead><tbody>"
    for (let r = 0; r < rows; r++) {
      html += `<tr><th class="napkin-row-header">${r + 1}</th>`
      for (let c = 0; c < cols; c++) {
        const ref = this.cellRef(c, r)
        const cell = cells.get(ref) || { raw: "", fmt: null }
        const display = this.computeDisplay(ref, cell)
        const cls = ["napkin-cell"]
        if (cell.fmt && cell.fmt.includes("bold")) cls.push("is-bold")
        if (display.error) cls.push("napkin-cell--error")
        if (this.isSelected(ref)) cls.push("is-selected")
        html += `<td class="${cls.join(" ")}" data-ref="${ref}" data-action="mousedown->napkin#cellMouseDown dblclick->napkin#editCell">${this.escape(display.text)}</td>`
      }
      html += "</tr>"
    }
    html += "</tbody></table>"
    el.innerHTML = html
    this.updateFormulaBar()
  }

  computeDisplay(ref, cell) {
    if (!cell || !cell.raw) return { text: "", error: null }
    if (cell.raw.startsWith("=")) {
      // Stub until parser loads (Task 10).
      return this.parser ? this.evaluateFormula(ref, cell) : { text: cell.raw, error: null }
    }
    return { text: this.formatNumeric(cell.raw, cell.fmt), error: null }
  }

  formatNumeric(raw, fmt) {
    const n = Number(raw)
    if (Number.isNaN(n) || raw.trim() === "") return raw
    return this.formatValue(n, fmt)
  }

  formatValue(n, fmt) {
    const parts = (fmt || "").split("|").filter(p => p && p !== "bold")
    const style = parts[0]
    if (!style) return Number.isInteger(n) ? String(n) : String(n)
    const m1 = /^number:(\d+)$/.exec(style)
    if (m1) return n.toFixed(parseInt(m1[1], 10))
    const m2 = /^currency:([A-Z]{3}):(\d+)$/.exec(style)
    if (m2) {
      const sym = ({ USD: "$", EUR: "€", GBP: "£", JPY: "¥" })[m2[1]] || `${m2[1]} `
      const dec = parseInt(m2[2], 10)
      return `${sym}${n.toFixed(dec).replace(/\B(?=(\d{3})+(?!\d))/g, ",")}`
    }
    const m3 = /^percent:(\d+)$/.exec(style)
    if (m3) return `${(n * 100).toFixed(parseInt(m3[1], 10))}%`
    return String(n)
  }

  evaluateFormula(_ref, cell) { return { text: cell.raw, error: null } } // wired in Task 10

  cellMouseDown(e) {
    const ref = e.currentTarget.dataset.ref
    this.state.selection = { anchor: ref, focus: ref }
    this.renderGrid()
  }

  editCell(e) {
    const ref = e.currentTarget.dataset.ref
    const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
    const td = e.currentTarget
    td.innerHTML = `<input class="napkin-cell-input" value="${this.escape(cell.raw)}">`
    const input = td.querySelector("input")
    input.focus()
    input.select()
    const commit = () => {
      const newRaw = input.value
      this.setCell(ref, { ...cell, raw: newRaw })
      this.renderGrid()
    }
    input.addEventListener("blur", commit)
    input.addEventListener("keydown", (kev) => {
      if (kev.key === "Enter") { commit(); }
      if (kev.key === "Escape") { this.renderGrid(); }
    })
  }

  setCell(ref, cell) {
    if (!cell.raw && !cell.fmt) this.state.cells.delete(ref)
    else this.state.cells.set(ref, cell)
    this.syncHiddenInput()
  }

  syncHiddenInput() {
    const cells = Object.fromEntries(this.state.cells)
    const hasAny = Object.keys(cells).length > 0
    this.hiddenInputTarget.value = hasAny
      ? JSON.stringify({ rows: this.state.rows, cols: this.state.cols, cells })
      : ""
  }

  isSelected(ref) {
    const sel = this.state.selection
    return sel && (ref === sel.focus || ref === sel.anchor)
  }

  updateFormulaBar() {
    if (!this.hasFormulaBarTarget) return
    const ref = this.state.selection.focus
    const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
    this.formulaRefTarget.textContent = ref
    this.formulaBarTarget.value = cell.raw
  }

  formulaBarEdit() {
    const ref = this.state.selection.focus
    const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
    this.setCell(ref, { ...cell, raw: this.formulaBarTarget.value })
    this.renderGrid()
  }

  formulaBarKey() {} // no-op for now

  applyFormat() {} // wired in Task 11
  toggleBold()  {} // wired in Task 11
  addRow()      {} // wired in Task 12
  addCol()      {} // wired in Task 12

  ensureParserLoaded() {} // wired in Task 10

  escape(s) {
    return String(s).replace(/[&<>"']/g, (m) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[m])
  }
}
```

- [ ] **Step 2: Register controller**

Open `app/javascript/controllers/index.js`. Add:

```javascript
import NapkinController from "./napkin_controller"
application.register("napkin", NapkinController)
```

(Match the file's existing registration pattern — the existing controllers tell you the exact import/register syntax. If the project uses `eager_load_controllers`/`stimulus-loading`, confirm before adding manually; otherwise add the explicit import + register.)

- [ ] **Step 3: Build and verify in browser**

Run: `yarn build`
Expected: build succeeds.

Run: `bin/dev` and load `/ideas/<id>/edit` for an idea with no napkin data.

Manual checks:
- Click "Back-of-the-napkin" header → panel expands.
- Click another time → collapses.
- Expand again. Click a cell → blue selection outline.
- Double-click a cell → input appears, type "Users", press Enter → cell now shows "Users".
- Click another cell, double-click, type `1000` Enter → "1000".
- Submit form. Reload edit page. Cells should persist.

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/napkin_controller.js app/javascript/controllers/index.js
git commit -m "js: napkin Stimulus controller — render, edit, persist (no formulas yet)"
```

---

## Task 10: Lazy-load `hot-formula-parser` and wire formula evaluation

**Files:**
- Modify: `app/javascript/controllers/napkin_controller.js`

> Note: Task 9 was merged into Task 8. Keeping numbering forward.

- [ ] **Step 1: Replace `ensureParserLoaded` and `evaluateFormula`**

In `app/javascript/controllers/napkin_controller.js`, replace the `ensureParserLoaded()` and `evaluateFormula()` methods:

```javascript
  async ensureParserLoaded() {
    if (this.parser || this.parserLoading) return
    this.parserLoading = true
    if (this.hasLoadingTarget) this.loadingTarget.classList.remove("hidden")
    try {
      const mod = await import("hot-formula-parser")
      const Parser = mod.Parser || mod.default?.Parser || mod.default
      this.parser = new Parser()
      this.parser.on("callCellValue", (ref, done) => {
        const r = `${ref.column.label}${ref.row.label + 1 || ref.row.index + 1}`
        done(this.cellNumericValue(r, new Set()))
      })
      this.parser.on("callRangeValue", (start, end, done) => {
        const out = []
        for (let r = start.row.index; r <= end.row.index; r++) {
          const row = []
          for (let c = start.column.index; c <= end.column.index; c++) {
            const ref = `${COL_LETTERS[c]}${r + 1}`
            row.push(this.cellNumericValue(ref, new Set()))
          }
          out.push(row)
        }
        done(out)
      })
      this.renderGrid()
    } finally {
      this.parserLoading = false
      if (this.hasLoadingTarget) this.loadingTarget.classList.add("hidden")
    }
  }

  cellNumericValue(ref, visited) {
    if (visited.has(ref)) return { error: "#CYCLE" }
    visited.add(ref)
    const cell = this.state.cells.get(ref)
    if (!cell || !cell.raw) return null
    if (cell.raw.startsWith("=")) {
      const inner = this.evalRaw(cell.raw.slice(1), visited)
      return inner.error ? { error: inner.error } : inner.value
    }
    const n = Number(cell.raw)
    return Number.isNaN(n) ? cell.raw : n
  }

  evalRaw(expr, visited) {
    if (!this.parser) return { value: null, error: "#ERR" }
    // The parser internally re-enters callCellValue/callRangeValue. We swap visited via a closure
    // by stashing it on the instance for the duration of the parse.
    const prev = this._visited
    this._visited = visited
    try {
      const { error, result } = this.parser.parse(expr)
      if (error) return { value: null, error: this.mapError(error) }
      return { value: result, error: null }
    } finally {
      this._visited = prev
    }
  }

  mapError(err) {
    const s = String(err)
    if (s.includes("CYCLE")) return "#CYCLE"
    if (s.includes("#REF")) return "#REF"
    if (s.includes("DIV")) return "#DIV/0"
    return "#ERR"
  }

  evaluateFormula(ref, cell) {
    if (!this.parser) return { text: cell.raw, error: null }
    const { value, error } = this.evalRaw(cell.raw.slice(1), new Set([ref]))
    if (error) return { text: error, error }
    return { text: typeof value === "number" ? this.formatValue(value, cell.fmt) : String(value), error: null }
  }
```

Also adjust `cellNumericValue` so it inherits `this._visited` when present:

```javascript
  cellNumericValue(ref, visited) {
    visited = this._visited || visited
    if (visited.has(ref)) return { error: "#CYCLE" }
    visited.add(ref)
    const cell = this.state.cells.get(ref)
    if (!cell || !cell.raw) return null
    if (cell.raw.startsWith("=")) {
      const inner = this.evalRaw(cell.raw.slice(1), visited)
      return inner.error ? { error: inner.error } : inner.value
    }
    const n = Number(cell.raw)
    return Number.isNaN(n) ? cell.raw : n
  }
```

- [ ] **Step 2: Build**

Run: `yarn build`
Expected: succeeds; bundle creates a separate chunk for `hot-formula-parser` (dynamic import).

- [ ] **Step 3: Manual verify**

In `bin/dev`, on an idea edit page:
- Expand panel → "Loading formula engine…" briefly appears, then disappears.
- Type into A1: `10`, A2: `20`, A3: `=A1+A2` Enter → A3 shows `30`.
- Type B1: `=SUM(A1:A2)` → `30`.
- Type C1: `=IF(A3>25, "high", "low")` → `high`.
- Type D1: `=D1` → `#CYCLE`.
- Save form, reload → values persist, formulas re-evaluate to same results.
- Visit show page → server-side dentaku eval renders the same numbers (parity check).

- [ ] **Step 4: Commit**

```bash
git add app/javascript/controllers/napkin_controller.js
git commit -m "js: lazy-load hot-formula-parser and wire formula evaluation"
```

---

## Task 11: Range selection + format toolbar

**Files:**
- Modify: `app/javascript/controllers/napkin_controller.js`

- [ ] **Step 1: Add range-selection logic**

Replace `cellMouseDown` and add helpers:

```javascript
  cellMouseDown(e) {
    e.preventDefault()
    const ref = e.currentTarget.dataset.ref
    this.state.selection = { anchor: ref, focus: ref }
    this._dragging = true
    this.renderGrid()
    const onEnter = (ev) => {
      const r = ev.target?.dataset?.ref
      if (this._dragging && r) { this.state.selection.focus = r; this.renderGrid() }
    }
    const onUp = () => {
      this._dragging = false
      this.gridTarget.removeEventListener("mouseover", onEnter)
      window.removeEventListener("mouseup", onUp)
    }
    this.gridTarget.addEventListener("mouseover", onEnter)
    window.addEventListener("mouseup", onUp)
  }

  selectionCells() {
    const a = this.parseRef(this.state.selection.anchor)
    const f = this.parseRef(this.state.selection.focus)
    if (!a || !f) return []
    const c1 = Math.min(a.c, f.c), c2 = Math.max(a.c, f.c)
    const r1 = Math.min(a.r, f.r), r2 = Math.max(a.r, f.r)
    const out = []
    for (let c = c1; c <= c2; c++)
      for (let r = r1; r <= r2; r++)
        out.push(this.cellRef(c, r))
    return out
  }

  isSelected(ref) {
    const a = this.parseRef(this.state.selection.anchor)
    const f = this.parseRef(this.state.selection.focus)
    const p = this.parseRef(ref)
    if (!a || !f || !p) return false
    const c1 = Math.min(a.c, f.c), c2 = Math.max(a.c, f.c)
    const r1 = Math.min(a.r, f.r), r2 = Math.max(a.r, f.r)
    return p.c >= c1 && p.c <= c2 && p.r >= r1 && p.r <= r2
  }
```

- [ ] **Step 2: Wire format toolbar**

Replace the `applyFormat()` and `toggleBold()` stubs:

```javascript
  applyFormat() {
    const style = this.fmtSelectTarget.value
    const dec = parseInt(this.decimalsInputTarget.value, 10) || 0
    let fmtStyle = ""
    if (style === "number") fmtStyle = `number:${dec}`
    else if (style.startsWith("currency:")) fmtStyle = `${style}:${dec}`
    else if (style === "percent") fmtStyle = `percent:${dec}`

    this.selectionCells().forEach((ref) => {
      const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
      const bold = (cell.fmt || "").split("|").includes("bold")
      const merged = [bold ? "bold" : null, fmtStyle || null].filter(Boolean).join("|")
      this.setCell(ref, { ...cell, fmt: merged || null })
    })
    this.renderGrid()
  }

  toggleBold() {
    this.selectionCells().forEach((ref) => {
      const cell = this.state.cells.get(ref) || { raw: "", fmt: null }
      const parts = new Set((cell.fmt || "").split("|").filter(Boolean))
      parts.has("bold") ? parts.delete("bold") : parts.add("bold")
      this.setCell(ref, { ...cell, fmt: parts.size ? [...parts].join("|") : null })
    })
    this.renderGrid()
  }
```

- [ ] **Step 3: Add Delete-key handler**

Add a `keydown` listener inside `connect()` (at the end, before any return):

```javascript
    this.element.addEventListener("keydown", (e) => {
      if (e.key === "Delete" || e.key === "Backspace") {
        if (e.target.tagName === "INPUT") return
        e.preventDefault()
        this.selectionCells().forEach((ref) => this.setCell(ref, { raw: "", fmt: null }))
        this.renderGrid()
      }
    })
    this.element.tabIndex = 0
```

- [ ] **Step 4: Build and manual verify**

`yarn build`. In browser:
- Click+drag from A1 to C3 → 3×3 highlighted.
- Click bold button → all 9 cells bold.
- Choose "Currency (USD)" + decimals 0 → cells with numeric content render `$N`.
- Press Delete with selection active → cells clear.

- [ ] **Step 5: Commit**

```bash
git add app/javascript/controllers/napkin_controller.js
git commit -m "js: range selection + format toolbar (currency/percent/number/bold/delete)"
```

---

## Task 12: Add/remove rows and columns

**Files:**
- Modify: `app/javascript/controllers/napkin_controller.js`

- [ ] **Step 1: Replace `addRow()` and `addCol()` stubs and add removal helpers**

```javascript
  addRow() {
    if (this.state.rows >= 100) return
    this.state.rows += 1
    this.renderGrid()
    this.syncHiddenInput()
  }

  addCol() {
    if (this.state.cols >= 26) return
    this.state.cols += 1
    this.renderGrid()
    this.syncHiddenInput()
  }
```

(Row/col delete via right-click menu is out of scope for v1; only "+" buttons are exposed. If rows/cols are reduced manually via the JSON, cells beyond the new bounds remain in storage but are invisible — acceptable for v1.)

- [ ] **Step 2: Build and manual verify**

`yarn build`. In browser:
- Click "+ Row" → grid shows 11 rows.
- Click "+ Col" → grid shows 6 cols.
- Click "+ Col" 21 more times → caps at 26.

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/napkin_controller.js
git commit -m "js: add-row / add-col grid resize"
```

---

## Task 13: CSS styling

**Files:**
- Create: `app/assets/stylesheets/napkin.css`
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Create stylesheet**

Create `app/assets/stylesheets/napkin.css`:

```css
.napkin-panel { padding: 0; }
.napkin-header {
  display: flex; align-items: center; justify-content: space-between;
  padding: 12px 16px; cursor: pointer; user-select: none;
}
.napkin-header h3 { margin: 0; }
.napkin-toggle-btn {
  background: transparent; border: 0; cursor: pointer; padding: 4px;
  display: flex; align-items: center; color: var(--text-muted, #888);
}
.napkin-toggle-btn[aria-expanded="true"] .napkin-chevron { transform: rotate(180deg); }
.napkin-chevron { transition: transform .15s ease; }

.napkin-body { padding: 0 16px 16px; }
.napkin-body.hidden { display: none; }

.napkin-toolbar {
  display: flex; align-items: center; gap: 8px; flex-wrap: wrap;
  padding: 8px 0; border-bottom: 1px solid var(--border-default, #ddd);
}
.napkin-fmt-select, .napkin-decimals-input { padding: 4px 6px; font-size: 13px; }
.napkin-decimals-input { width: 56px; }
.napkin-bold-btn { padding: 2px 8px; font-weight: 700; cursor: pointer; }
.napkin-row-btn, .napkin-col-btn { padding: 2px 8px; cursor: pointer; }
.napkin-spacer { flex: 1; }

.napkin-formula-bar {
  display: flex; gap: 8px; align-items: center; padding: 8px 0;
  border-bottom: 1px solid var(--border-default, #ddd);
}
.napkin-formula-label {
  display: inline-block; min-width: 32px; padding: 2px 8px;
  background: var(--surface-2, #f0f0f0); border-radius: 3px; font-family: monospace; font-size: 12px;
}
.napkin-formula-input { flex: 1; padding: 4px 8px; font-family: monospace; font-size: 13px; }

.napkin-grid-wrap { overflow: auto; max-height: 480px; margin-top: 8px; }
.napkin-grid-table { border-collapse: collapse; font-size: 13px; }
.napkin-corner, .napkin-col-header, .napkin-row-header {
  background: var(--surface-2, #f4f4f4); padding: 4px 8px;
  border: 1px solid var(--border-default, #ccc); position: sticky; font-weight: 600;
}
.napkin-col-header { top: 0; }
.napkin-row-header { left: 0; }
.napkin-corner { top: 0; left: 0; z-index: 2; }
.napkin-cell {
  border: 1px solid var(--border-default, #ddd);
  min-width: 96px; height: 28px; padding: 2px 8px;
  cursor: cell; vertical-align: middle; text-align: right;
}
.napkin-cell:not([data-ref]) { text-align: left; }
.napkin-cell.is-bold { font-weight: 700; }
.napkin-cell.is-selected { outline: 2px solid var(--accent, #3b82f6); outline-offset: -2px; }
.napkin-cell--error { color: #b91c1c; font-style: italic; }
.napkin-cell-input {
  width: 100%; height: 100%; border: 0; padding: 0; background: transparent;
  font-family: inherit; font-size: inherit;
}

.napkin-loading { padding: 8px; font-size: 12px; color: var(--text-muted, #888); }
.napkin-loading.hidden { display: none; }

.napkin-readonly { overflow: auto; }
.napkin-grid--readonly .napkin-cell { cursor: default; }
```

- [ ] **Step 2: Import in application.css (or appropriate manifest)**

Open `app/assets/stylesheets/application.css`. Add (somewhere with the other `*= require` directives, or as `@import` if the file is plain CSS):

```css
*= require napkin
```

(Or `@import "./napkin.css";` — match the file's existing pattern.)

- [ ] **Step 3: Reload and verify**

In `bin/dev`, the napkin panel should render with proper grid lines, sticky headers, range highlight, bold styling.

- [ ] **Step 4: Commit**

```bash
git add app/assets/stylesheets/napkin.css app/assets/stylesheets/application.css
git commit -m "styles: napkin grid"
```

---

## Task 14: System test — full round-trip

**Files:**
- Create: `test/system/napkin_calculations_test.rb`

- [ ] **Step 1: Write the system test**

Create `test/system/napkin_calculations_test.rb`:

```ruby
require "application_system_test_case"

class NapkinCalculationsTest < ApplicationSystemTestCase
  setup do
    @user = User.first || User.create!(email: "napkin-sys@test.example", name: "Sys")
    @idea = @user.ideas.create!(title: "Sys napkin", state: :idea_new, attempt_count: 0)
  end

  test "user enters napkin formula and it persists and renders on show" do
    visit edit_idea_path(@idea)

    find(".napkin-header").click
    assert_selector ".napkin-grid-table", visible: true

    enter_cell("A1", "Users")
    enter_cell("B1", "1000")
    enter_cell("A2", "ARPU")
    enter_cell("B2", "50")
    enter_cell("A3", "Revenue")
    enter_cell("B3", "=B1*B2")

    click_button "Update Idea"

    @idea.reload
    assert_equal "1000", @idea.napkin_calculations["cells"]["B1"]["raw"]
    assert_equal "=B1*B2", @idea.napkin_calculations["cells"]["B3"]["raw"]

    visit idea_path(@idea)
    assert_selector ".napkin-readonly"
    within ".napkin-grid--readonly" do
      assert_text "Users"
      assert_text "Revenue"
      assert_text "50000" # rendered as integer with auto-format on the readonly side
    end
  end

  private

  def enter_cell(ref, value)
    cell = find(".napkin-cell[data-ref='#{ref}']")
    cell.double_click
    input = cell.find("input")
    input.fill_in with: value
    input.send_keys :enter
  end
end
```

- [ ] **Step 2: Run system test**

Run: `bin/rails test:system test/system/napkin_calculations_test.rb`
Expected: green.

If it fails on rendered Revenue value being `50,000.00` rather than `50000` — adjust the assertion to match the format your `format_napkin_cell` produces for auto-formatting (the helper test already pinned this; mirror it here).

- [ ] **Step 3: Run full test suite**

Run: `bin/rails test && bin/rails test:system`
Expected: all green.

- [ ] **Step 4: Commit**

```bash
git add test/system/napkin_calculations_test.rb
git commit -m "tests: system test for napkin grid round-trip"
```

---

## Self-Review Checklist (run before merging)

- [ ] Spec § Scope (in/out) maps to tasks 1–14? Yes.
- [ ] Spec § Data Model: column, serialize, helpers, validations? Tasks 2–3.
- [ ] Spec § Formula Engine: dentaku (server), hot-formula-parser (client lazy)? Tasks 1, 5, 10.
- [ ] Spec § UX collapsible panel? Task 7. Range selection? Task 11. Format toolbar? Task 11. Resize? Task 12. Read-only show? Task 6.
- [ ] All file paths concrete? Yes.
- [ ] All code blocks complete (no TBD)? Yes.
- [ ] Method names consistent (`napkin_present?`, `napkin_evaluate`, `format_napkin_cell`, `applyFormat`, `toggleBold`)? Yes.
- [ ] No "implement later" placeholders? Yes.
