module IdeaFormHelper
  # Inner content of a collapsible panel's <summary>: label, optional "Recommended"
  # badge, and a tick (done) that sits just left of the collapse arrow.
  def panel_title(label, done: false, recommended: false)
    safe_join([
      content_tag(:span, safe_join([ label, (content_tag(:span, "Recommended", class: "template-card-badge") if recommended) ].compact, " ")),
      (content_tag(:span, "✓", class: "form-panel-done", title: "Complete", "aria-label": "Complete") if done)
    ].compact)
  end

  # Plain-text "how is this score calculated" using the user's real weights.
  def weighted_score_explanation(idea, weights)
    terms = { "trl" => "TRL", "difficulty" => "Difficulty", "opportunity" => "Opportunity", "timing" => "Timing" }
      .map { |key, label| "#{label} x #{weights[key]}" }.join(" + ")
    primary = idea.template&.effective_primary_scoring_system_id
    scope = if primary.nil?
      "Each enabled scoring system is normalized to 0-10 and the weighted score is their average."
    else
      "This template uses #{idea.user&.scoring_system(primary)&.dig('name') || primary} as the weighted score."
    end
    "Weighted readiness = #{terms} (each rating 0-10), then rescaled to 0-10 so the lowest and highest possible results map to 0 and 10. #{scope} Change the weights in Settings."
  end
end
