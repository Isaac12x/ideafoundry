module AgentRecommendationsHelper
  IDEA_RECOMMENDATION_FIELDS = {
    "title" => "Title",
    "description" => "Description",
    "state" => "State",
    "trl" => "TRL",
    "difficulty" => "Difficulty",
    "opportunity" => "Opportunity",
    "timing" => "Timing",
    "difficulty_explanation" => "Difficulty notes",
    "opportunity_explanation" => "Opportunity notes",
    "timing_explanation" => "Timing notes",
    "metadata" => "Metadata"
  }.freeze

  INTERNAL_RECOMMENDATION_KEYS = %w[
    action arguments base_version_id commit_message files file_changes idea_id
    payload recommendation_id risk_level target_id target_type
  ].freeze

  def agent_recommendation_title(recommendation)
    case recommendation.action.to_s
    when "update_idea"
      "Refine this idea"
    when "transition_idea"
      "Move to #{agent_recommendation_preview_payload(recommendation)["state"].to_s.humanize}"
    when "create_note"
      "Add a note"
    when "create_todo"
      "Add a todo"
    when "assign_list"
      "Add to a list"
    when "assign_topology"
      "Attach topology"
    when "run_enrichment"
      "Run enrichment"
    else
      recommendation.action.to_s.humanize
    end
  end

  def agent_recommendation_preview_payload(recommendation)
    raw_payload = recommendation.payload || {}
    return {} unless raw_payload.respond_to?(:to_h)

    payload = raw_payload.to_h.deep_stringify_keys

    nested_payload = payload["payload"]
    nested_arguments = payload["arguments"]
    meaningful_keys = IDEA_RECOMMENDATION_FIELDS.keys + %w[append body title files file_changes]

    if nested_payload.is_a?(Hash) && (payload.keys & meaningful_keys).empty?
      nested_payload.deep_stringify_keys
    elsif nested_arguments.is_a?(Hash) && (payload.keys & meaningful_keys).empty?
      nested_arguments.deep_stringify_keys
    else
      payload
    end
  end

  def agent_recommendation_field_changes(recommendation, idea)
    payload = agent_recommendation_preview_payload(recommendation)
    payload = payload.merge("state" => payload["state"]) if recommendation.action.to_s == "transition_idea" && payload["state"].present?

    IDEA_RECOMMENDATION_FIELDS.filter_map do |field, label|
      next unless payload.key?(field) || (field == "description" && payload.key?("append"))

      current = agent_recommendation_current_idea_value(idea, field)
      proposed = agent_recommendation_proposed_value(current, payload, field)
      next if agent_recommendation_comparable_value(current) == agent_recommendation_comparable_value(proposed)

      {
        field: field,
        label: label,
        from: agent_recommendation_display_value(current),
        to: agent_recommendation_display_value(proposed)
      }
    end
  end

  def agent_recommendation_additions(recommendation)
    payload = agent_recommendation_preview_payload(recommendation)

    additions = case recommendation.action.to_s
                when "create_note"
                  [{ label: "Note", title: "New note", body: payload["body"] }]
                when "create_todo"
                  [{ label: "Todo", title: payload["title"].presence || "New todo", body: payload["body"] || payload["title"] }]
                when "create_fact"
                  [{ label: "Fact", title: "Knowledge base fact", body: payload["body"] }]
                when "create_maxim"
                  [{ label: "Maxim", title: "Knowledge base maxim", body: payload["body"] }]
                when "run_enrichment"
                  [{ label: "Enrichment", title: payload["query"].presence || "Use current idea context", body: payload.except("idea_id").to_json }]
                else
                  []
                end

    generic = payload.except(*(IDEA_RECOMMENDATION_FIELDS.keys + INTERNAL_RECOMMENDATION_KEYS))
    if additions.empty? && generic.present?
      additions << {
        label: "Action",
        title: recommendation.action.to_s.humanize,
        body: JSON.pretty_generate(generic)
      }
    end

    additions.filter_map do |addition|
      body = addition[:body].to_s
      next if body.blank?

      addition.merge(body: body)
    end
  end

  def agent_recommendation_file_additions(recommendation)
    payload = agent_recommendation_preview_payload(recommendation)
    files = payload["files"].presence || payload["file_changes"].presence || []

    Array(files).filter_map.with_index do |file, index|
      if file.is_a?(Hash)
        file = file.deep_stringify_keys
        content = file["content"] || file["body"] || file["text"] || file.except("path", "name", "filename").to_json
        path = file["path"].presence || file["filename"].presence || file["name"].presence || "Suggested file #{index + 1}"
      else
        content = file.to_s
        path = "Suggested file #{index + 1}"
      end

      next if content.blank?

      { path: path, content: content.to_s }
    end
  end

  def agent_recommendation_line_diff(from_value, to_value)
    old_lines = agent_recommendation_diff_lines(from_value)
    new_lines = agent_recommendation_diff_lines(to_value)
    return [{ kind: "same", old_number: nil, new_number: nil, text: "" }] if old_lines.empty? && new_lines.empty?

    lcs = Array.new(old_lines.length + 1) { Array.new(new_lines.length + 1, 0) }
    (old_lines.length - 1).downto(0) do |old_index|
      (new_lines.length - 1).downto(0) do |new_index|
        lcs[old_index][new_index] =
          if old_lines[old_index] == new_lines[new_index]
            lcs[old_index + 1][new_index + 1] + 1
          else
            [lcs[old_index + 1][new_index], lcs[old_index][new_index + 1]].max
          end
      end
    end

    old_index = 0
    new_index = 0
    old_number = 1
    new_number = 1
    diff = []

    while old_index < old_lines.length && new_index < new_lines.length
      if old_lines[old_index] == new_lines[new_index]
        diff << { kind: "same", old_number: old_number, new_number: new_number, text: old_lines[old_index] }
        old_index += 1
        new_index += 1
        old_number += 1
        new_number += 1
      elsif lcs[old_index + 1][new_index] >= lcs[old_index][new_index + 1]
        diff << { kind: "delete", old_number: old_number, new_number: nil, text: old_lines[old_index] }
        old_index += 1
        old_number += 1
      else
        diff << { kind: "insert", old_number: nil, new_number: new_number, text: new_lines[new_index] }
        new_index += 1
        new_number += 1
      end
    end

    while old_index < old_lines.length
      diff << { kind: "delete", old_number: old_number, new_number: nil, text: old_lines[old_index] }
      old_index += 1
      old_number += 1
    end

    while new_index < new_lines.length
      diff << { kind: "insert", old_number: nil, new_number: new_number, text: new_lines[new_index] }
      new_index += 1
      new_number += 1
    end

    diff
  end

  private

  def agent_recommendation_current_idea_value(idea, field)
    case field
    when "description"
      idea.description.to_plain_text
    when "metadata"
      idea.metadata || {}
    else
      idea.public_send(field) if idea.respond_to?(field)
    end
  end

  def agent_recommendation_proposed_value(current, payload, field)
    if field == "description" && payload.key?("append") && !payload.key?("description")
      [current, payload["append"]].map(&:to_s).reject(&:blank?).join("\n\n")
    else
      payload[field]
    end
  end

  def agent_recommendation_display_value(value)
    case value
    when Hash, Array
      JSON.pretty_generate(value)
    else
      value.to_s
    end
  end

  def agent_recommendation_comparable_value(value)
    agent_recommendation_display_value(value).strip
  end

  def agent_recommendation_diff_lines(value)
    text = value.to_s
    return [] if text.blank?

    text.lines(chomp: true)
  end
end
