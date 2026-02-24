class WebhooksController < ActionController::API
  before_action :authenticate_token

  def external
    event = params[:event].to_s
    payload = params[:payload] || {}
    content = params[:content]

    user = User.first
    return head :unprocessable_entity unless user

    case event
    when "create_idea"
      idea = user.ideas.create!(
        title: payload[:title] || "Webhook idea",
        state: :idea_new,
        attempt_count: 0,
        metadata: { source: "webhook", content: content }
      )
      render json: { status: "created", idea_id: idea.id }, status: :accepted

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

  def authenticate_token
    token = request.headers["Authorization"]&.remove("Bearer ")
    expected = Rails.application.credentials.dig(:external_webhook, :token)

    unless expected.present? && ActiveSupport::SecurityUtils.secure_compare(token.to_s, expected)
      head :unauthorized
    end
  end
end
