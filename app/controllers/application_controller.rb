class ApplicationController < ActionController::Base
  TYPING_ACTIVITY_SESSION_KEY = "typing_last_activity_at"
  TYPING_LOCK_RETURN_TO_SESSION_KEY = "typing_lock_return_to"
  LEGACY_TYPING_UNLOCK_SESSION_KEY = "typing_unlocked_at"
  TYPING_AUTHENTICATOR_PENDING_SESSION_KEY = "typing_authenticator_pending_at"
  TYPING_AUTHENTICATOR_RETURN_TO_SESSION_KEY = "typing_authenticator_return_to"
  TYPING_AUTHENTICATOR_TIMEOUT = 5.minutes
  VOICE_ID_PENDING_SESSION_KEY = "voice_id_pending_at"
  VOICE_ID_RETURN_TO_SESSION_KEY = "voice_id_return_to"
  VOICE_ID_TIMEOUT = 5.minutes

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
    return unless @user&.security_lock_enabled?
    return if typing_session_unlocked?

    target = safe_return_path(request.fullpath)

    if @user.typing_lock_enabled? && !@user.typing_fingerprint_configured?
      redirect_for_typing_lock(enroll_typing_lock_path(return_to: target))
    elsif @user.voice_id_requested? && !@user.voice_id_configured?
      redirect_for_typing_lock(enroll_voice_id_path(return_to: target))
    elsif typing_lock_root_display_request?
      render_first_security_lock(return_to: typing_lock_return_to_path(target))
    else
      remember_typing_lock_return_to!(target)
      redirect_for_typing_lock(root_path)
    end
  end

  def typing_session_unlocked?
    last_activity_at = typing_last_activity_at
    return false if last_activity_at.zero?

    if last_activity_at >= @user.security_lock_timeout_seconds.seconds.ago.to_i
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
    clear_voice_id_challenge!
    clear_typing_lock_return_to!
    touch_typing_session_activity!
  end

  def expire_typing_session!
    session.delete(LEGACY_TYPING_UNLOCK_SESSION_KEY)
    session.delete(TYPING_ACTIVITY_SESSION_KEY)
    clear_typing_authenticator_challenge!
    clear_voice_id_challenge!
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

  def begin_voice_id_challenge!(return_to)
    safe_return_to = safe_return_path(return_to)
    session[VOICE_ID_PENDING_SESSION_KEY] = Time.current.to_i
    session[VOICE_ID_RETURN_TO_SESSION_KEY] = safe_return_to
  end

  def voice_id_challenge_pending?
    pending_at = session[VOICE_ID_PENDING_SESSION_KEY].to_i
    return false unless pending_at.positive?

    if pending_at >= VOICE_ID_TIMEOUT.ago.to_i
      true
    else
      clear_voice_id_challenge!
      false
    end
  end

  def voice_id_return_to
    safe_return_path(session[VOICE_ID_RETURN_TO_SESSION_KEY])
  end

  def clear_voice_id_challenge!
    session.delete(VOICE_ID_PENDING_SESSION_KEY)
    session.delete(VOICE_ID_RETURN_TO_SESSION_KEY)
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

  def render_first_security_lock(return_to:)
    if @user.typing_lock_enabled?
      render_typing_lock_unlock(return_to: return_to)
    elsif @user.authenticator_app_enabled?
      @return_to = return_to
      @authenticator_challenge_token = begin_typing_authenticator_challenge!(return_to)
      render "typing_locks/authenticator", status: :ok
    elsif @user.voice_id_enabled?
      render_voice_id_unlock(return_to: return_to)
    end
  end

  def render_typing_lock_unlock(return_to:)
    if (failed_unlock = @user.active_typing_lock_failed_unlock)
      @unlock_result = :missed
      @unlock_failure = failed_unlock
      @challenge_id = failed_unlock["challenge_id"].presence || ""
      @challenge_text = ""
    else
      @challenge_id = params[:challenge_id].presence || TypingTextLibrary.random_unlock_id
      @challenge_text = TypingTextLibrary.unlock_text(@challenge_id)
    end
    @return_to = return_to
    render "typing_locks/new", status: :ok
  end

  def render_voice_id_unlock(return_to:, error: nil, opening: false)
    begin_voice_id_challenge!(return_to) unless voice_id_challenge_pending?
    @return_to = return_to
    @voice_id_phrase = VoiceFingerprint::CANONICAL_PHRASE
    @voice_id_error = error
    @voice_id_opening = opening
    render "typing_locks/voice", status: error.present? ? :unprocessable_content : :ok
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
