class ApplicationController < ActionController::Base
  TYPING_ACTIVITY_SESSION_KEY = "typing_last_activity_at"
  TYPING_LOCK_RETURN_TO_SESSION_KEY = "typing_lock_return_to"
  LEGACY_TYPING_UNLOCK_SESSION_KEY = "typing_unlocked_at"
  TYPING_AUTHENTICATOR_PENDING_SESSION_KEY = "typing_authenticator_pending_at"
  TYPING_AUTHENTICATOR_RETURN_TO_SESSION_KEY = "typing_authenticator_return_to"
  TYPING_AUTHENTICATOR_TIMEOUT = 5.minutes

  helper_method :backlog_enabled?

  prepend_before_action :set_user
  before_action :require_typing_unlock

  private

  def set_user
    @user = User.first || User.create!(email: 'user@example.com', name: 'Default User')
  end

  def require_backlog_enabled
    return if backlog_enabled?

    redirect_to root_path, alert: "Backlog is not enabled."
  end

  def backlog_enabled?
    Rails.application.config.x.backlog_enabled == true
  end

  def require_typing_unlock
    set_user unless defined?(@user) && @user
    return unless @user&.typing_lock_enabled?
    return if typing_session_unlocked?

    target = safe_return_path(request.fullpath)

    if @user.typing_fingerprint_configured?
      if typing_lock_root_display_request?
        render_typing_lock_unlock(return_to: typing_lock_return_to_path(target))
      else
        remember_typing_lock_return_to!(target)
        redirect_for_typing_lock(root_path)
      end
    else
      redirect_for_typing_lock(enroll_typing_lock_path(return_to: target))
    end
  end

  def typing_session_unlocked?
    last_activity_at = typing_last_activity_at
    return false if last_activity_at.zero?

    if last_activity_at >= @user.typing_lock_timeout_seconds.seconds.ago.to_i
      touch_typing_session_activity!
      true
    else
      session.delete(LEGACY_TYPING_UNLOCK_SESSION_KEY)
      session.delete(TYPING_ACTIVITY_SESSION_KEY)
      false
    end
  end

  def unlock_typing_session!
    clear_typing_authenticator_challenge!
    clear_typing_lock_return_to!
    touch_typing_session_activity!
  end

  def expire_typing_session!
    session.delete(LEGACY_TYPING_UNLOCK_SESSION_KEY)
    session.delete(TYPING_ACTIVITY_SESSION_KEY)
    clear_typing_authenticator_challenge!
  end

  def begin_typing_authenticator_challenge!(return_to)
    safe_return_to = safe_return_path(return_to)
    session[TYPING_AUTHENTICATOR_PENDING_SESSION_KEY] = Time.current.to_i
    session[TYPING_AUTHENTICATOR_RETURN_TO_SESSION_KEY] = safe_return_to
    typing_authenticator_verifier.generate({
      "return_to" => safe_return_to,
      "issued_at" => Time.current.to_i
    })
  end

  def typing_authenticator_challenge_pending?
    pending_at = session[TYPING_AUTHENTICATOR_PENDING_SESSION_KEY].to_i
    return false unless pending_at.positive?

    if pending_at >= TYPING_AUTHENTICATOR_TIMEOUT.ago.to_i
      true
    else
      clear_typing_authenticator_challenge!
      false
    end
  end

  def typing_authenticator_return_to
    safe_return_path(session[TYPING_AUTHENTICATOR_RETURN_TO_SESSION_KEY])
  end

  def typing_authenticator_challenge_return_to(token)
    data = typing_authenticator_verifier.verify(token.to_s)
    issued_at = data["issued_at"].to_i
    return if issued_at < TYPING_AUTHENTICATOR_TIMEOUT.ago.to_i

    safe_return_path(data["return_to"])
  rescue ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def clear_typing_authenticator_challenge!
    session.delete(TYPING_AUTHENTICATOR_PENDING_SESSION_KEY)
    session.delete(TYPING_AUTHENTICATOR_RETURN_TO_SESSION_KEY)
  end

  def remember_typing_lock_return_to!(value)
    session[TYPING_LOCK_RETURN_TO_SESSION_KEY] = safe_typing_lock_return_path(value)
  end

  def typing_lock_return_to_path(default)
    safe_typing_lock_return_path(session[TYPING_LOCK_RETURN_TO_SESSION_KEY].presence || default)
  end

  def clear_typing_lock_return_to!
    session.delete(TYPING_LOCK_RETURN_TO_SESSION_KEY)
  end

  def render_typing_lock_unlock(return_to:)
    @challenge_id = params[:challenge_id].presence || TypingTextLibrary.random_unlock_id
    @challenge_text = TypingTextLibrary.unlock_text(@challenge_id)
    @return_to = return_to
    render "typing_locks/new", status: :ok
  end

  def touch_typing_session_activity!
    session[TYPING_ACTIVITY_SESSION_KEY] = Time.current.to_i
    session.delete(LEGACY_TYPING_UNLOCK_SESSION_KEY)
  end

  def redirect_for_typing_lock(path)
    if request.format.json?
      render json: { error: "Typing lock required" }, status: :unauthorized
    else
      redirect_to path
    end
  end

  def safe_return_path(value)
    path = value.presence || root_path
    uri = URI.parse(path)
    return path if uri.host.blank? && path.start_with?("/")

    root_path
  rescue URI::InvalidURIError
    root_path
  end

  def safe_typing_lock_return_path(value)
    path = safe_return_path(value)
    path.start_with?("/typing-lock") ? root_path : path
  end

  def typing_lock_root_display_request?
    request.get? && request.path == root_path && request.format.html?
  end

  def typing_last_activity_at
    activity_at = session[TYPING_ACTIVITY_SESSION_KEY].to_i
    return activity_at if activity_at.positive?

    session[LEGACY_TYPING_UNLOCK_SESSION_KEY].to_i
  end

  def typing_authenticator_verifier
    Rails.application.message_verifier(:typing_authenticator_challenge)
  end
end
