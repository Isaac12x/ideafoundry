class WebhooksController < ActionController::API
  before_action :authenticate_token

  def external
    event = params[:event].to_s
    payload = normalized_payload
    content = params[:content]

    user = User.first
    return head :unprocessable_content unless user

    if intake_event?(event, payload)
      result = IntakeSubmissionService.new(
        user: user,
        title: payload[:title],
        body: content.presence || payload[:body],
        source: payload[:source] || "webhook",
        source_reference: payload[:source_reference] || payload[:message_id] || payload[:thread_id],
        priority: payload[:priority],
        raw_payload: params.to_unsafe_h.except(:controller, :action),
        temporary_idea_id: payload[:temporary_idea_id] || payload[:intake_reference] || params[:temporary_idea_id]
      ).call

      render json: {
        status: result.created? ? "queued" : "updated",
        submission_id: result.submission.id,
        temporary_idea_id: result.submission.temporary_idea_id,
        idea_id: result.submission.idea_id,
        target: result.target_type
      }, status: :accepted
    else
      idea = user.ideas.find_by(id: payload[:idea_id])
      return head :not_found unless idea

      # Update idea metadata with webhook content
      idea.metadata ||= {}
      idea.metadata["last_webhook_event"] = event
      idea.metadata["last_webhook_content"] = content if content.present?
      idea.save!

      if user.notification_enabled?("webhook_triggered")
        EventNotificationJob.perform_later(
          idea_id: idea.id,
          user_id: user.id,
          event_type: "webhook_triggered",
          metadata: {
            idea_title: idea.title,
            webhook_event: event,
            content: content
          }
        )
      end

      render json: { status: "accepted", idea_id: idea.id }, status: :accepted
    end
  end

  private

  def normalized_payload
    payload = params[:payload]
    hash = if payload.respond_to?(:to_unsafe_h)
             payload.to_unsafe_h
           else
             payload.to_h
           end
    hash.with_indifferent_access
  rescue NoMethodError
    {}.with_indifferent_access
  end

  def intake_event?(event, payload)
    event == "create_idea" || payload[:temporary_idea_id].present? || payload[:intake_reference].present?
  end

  def authenticate_token
    token = request.headers["Authorization"]&.delete_prefix("Bearer ")
    expected = Rails.application.credentials.dig(:external_webhook, :token)

    unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
      head :unauthorized
    end
  end
end
