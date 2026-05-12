class TypingLocksController < ApplicationController
  skip_before_action :require_typing_unlock

  def new
    return redirect_to enroll_typing_lock_path(return_to: return_to_path) unless @user.typing_fingerprint_configured?

    @challenge_id = params[:challenge_id].presence || TypingTextLibrary.random_unlock_id
    @challenge_text = TypingTextLibrary.unlock_text(@challenge_id)
    @return_to = return_to_path
  end

  def verify
    @challenge_id = params[:challenge_id].to_s
    @challenge_text = TypingTextLibrary.unlock_text(@challenge_id)
    @return_to = return_to_path

    match = TypingFingerprint.match(
      template: @user.typing_fingerprint || {},
      events: timing_events,
      expected_text: @challenge_text
    )

    if match.passed?
      if @user.authenticator_app_enabled?
        @authenticator_challenge_token = begin_typing_authenticator_challenge!(@return_to)
        render :authenticator, status: :ok
      else
        render_unlock_success
      end
    else
      @unlock_result = :missed
      render :new, status: :unprocessable_content
    end
  end

  def verify_authenticator
    challenge_return_to = typing_authenticator_challenge_return_to(params[:authenticator_challenge])
    @return_to = challenge_return_to || typing_authenticator_return_to

    unless @user.authenticator_app_enabled? && (challenge_return_to.present? || typing_authenticator_challenge_pending?)
      redirect_to typing_lock_path(return_to: @return_to)
      return
    end

    if AuthenticatorApp.verify_code(@user.authenticator_app_secret, params[:authenticator_code])
      render_unlock_success
    else
      @authenticator_challenge_token = params[:authenticator_challenge]
      @authenticator_error = "Invalid authenticator code"
      render :authenticator, status: :unprocessable_content
    end
  end

  def activity
    return render json: { ok: true } unless @user.typing_lock_enabled?

    if typing_session_unlocked?
      render json: {
        ok: true,
        expires_at: @user.typing_lock_timeout_seconds.seconds.from_now.to_i
      }
    else
      render json: { error: "Typing lock required" }, status: :unauthorized
    end
  end

  def lock
    expire_typing_session!
    redirect_to typing_lock_path(return_to: return_to_path)
  end

  def enroll
    @challenge_id = params[:challenge_id].presence || TypingTextLibrary.random_enrollment_id
    @challenge_text = TypingTextLibrary.enrollment_text(@challenge_id)
    @return_to = return_to_path
  end

  def create
    @challenge_id = params[:challenge_id].to_s
    @challenge_text = TypingTextLibrary.enrollment_text(@challenge_id)
    @return_to = return_to_path

    fingerprint = TypingFingerprint.build(events: timing_events, expected_text: @challenge_text)

    if fingerprint["sample_count"] >= TypingFingerprint::MIN_ENROLLMENT_SAMPLE_COUNT
      @user.store_typing_fingerprint!(fingerprint)
      unlock_typing_session!
      redirect_to @return_to
    else
      flash.now[:alert] = "Type the full passage before storing the fingerprint."
      render :enroll, status: :unprocessable_content
    end
  end

  private

  def timing_events
    JSON.parse(params[:timing_payload].presence || "[]")
  rescue JSON::ParserError
    []
  end

  def return_to_path
    safe_return_path(params[:return_to])
  end

  def render_unlock_success
    unlock_typing_session!
    @unlock_result = :matched
    @unlock_redirect_url = @return_to
    @challenge_id ||= ""
    @challenge_text ||= ""
    render :new, status: :ok
  end
end
