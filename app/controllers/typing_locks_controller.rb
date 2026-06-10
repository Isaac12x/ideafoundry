class TypingLocksController < ApplicationController
  skip_before_action :require_typing_unlock

  def new
    return redirect_to enroll_typing_lock_path(return_to: return_to_path) unless @user.typing_fingerprint_configured?

    @return_to = return_to_path
    return if render_failed_unlock_cooldown(status: :ok)

    @challenge_id = params[:challenge_id].presence || TypingTextLibrary.random_unlock_id
    @challenge_text = TypingTextLibrary.unlock_text(@challenge_id)
  end

  def verify
    @challenge_id = params[:challenge_id].to_s
    @challenge_text = TypingTextLibrary.unlock_text(@challenge_id)
    @return_to = return_to_path
    return if render_failed_unlock_cooldown(status: :too_many_requests)

    match = TypingFingerprint.match(
      template: @user.typing_fingerprint || {},
      events: timing_events,
      expected_text: @challenge_text
    )

    if match.passed?
      render_next_security_lock_after(:typing)
    else
      @unlock_result = :missed
      @unlock_failure = @user.record_typing_lock_failed_unlock!(match:, challenge_id: @challenge_id)
      render :new, status: :unprocessable_content
    end
  end

  def verify_authenticator
    challenge_return_to = typing_authenticator_challenge_return_to(params[:authenticator_challenge])
    @return_to = challenge_return_to || typing_authenticator_return_to

    unless @user.authenticator_app_enabled? && (challenge_return_to.present? || typing_authenticator_challenge_pending?)
      remember_typing_lock_return_to!(@return_to)
      redirect_to root_path
      return
    end

    if AuthenticatorApp.verify_code(@user.authenticator_app_secret, params[:authenticator_code])
      render_next_security_lock_after(:authenticator)
    else
      @authenticator_challenge_token = params[:authenticator_challenge]
      @authenticator_error = "Invalid authenticator code"
      render :authenticator, status: :unprocessable_content
    end
  end

  def activity
    return render json: { ok: true } unless @user.security_lock_enabled?

    if typing_session_unlocked?
      render json: {
        ok: true,
        expires_at: @user.security_lock_timeout_seconds.seconds.from_now.to_i
      }
    else
      render json: { error: "Typing lock required" }, status: :unauthorized
    end
  end

  def lock
    remember_typing_lock_return_to!(return_to_path)
    expire_typing_session!
    redirect_to root_path
  end

  def enroll
    @challenge_id = params[:challenge_id].presence || TypingTextLibrary.random_enrollment_id
    @challenge_text = TypingTextLibrary.enrollment_text(@challenge_id)
    @return_to = return_to_path
  end

  def enroll_voice
    @return_to = return_to_path
    @voice_id_phrase = VoiceFingerprint::CANONICAL_PHRASE
    @voice_id_variants = VoiceFingerprint::SETUP_VARIANTS
  end

  def create_voice
    @return_to = return_to_path
    fingerprint = VoiceFingerprint.build(samples: voice_id_samples)

    if fingerprint["sample_count"].to_i >= VoiceFingerprint::MIN_ENROLLMENT_SAMPLE_COUNT
      @user.store_voice_id_fingerprint!(fingerprint)
      unlock_typing_session! unless @user.typing_lock_enabled? || @user.authenticator_app_enabled?
      redirect_to @return_to
    else
      @voice_id_phrase = VoiceFingerprint::CANONICAL_PHRASE
      @voice_id_variants = VoiceFingerprint::SETUP_VARIANTS
      flash.now[:alert] = "Say the voice phrase three times before storing Voice ID."
      render :enroll_voice, status: :unprocessable_content
    end
  end

  def verify_voice
    @return_to = voice_id_return_to.presence || return_to_path

    unless @user.voice_id_enabled? && voice_id_challenge_pending?
      remember_typing_lock_return_to!(@return_to)
      redirect_to root_path
      return
    end

    if VoiceFingerprint.match?(template: @user.voice_id_fingerprint, transcript: voice_transcript, sample: voice_payload)
      render_unlock_success(voice: true)
    else
      render_voice_id_unlock(return_to: @return_to, error: "Voice ID did not match. Say the exact phrase again.")
    end
  end

  def transcribe_voice
    audio = params[:audio]
    result = LocalVoiceIdClient.transcribe(
      audio: audio&.tempfile,
      filename: audio&.original_filename,
      content_type: audio&.content_type,
      duration_ms: params[:duration_ms],
      rms: params[:rms]
    )

    render json: result
  rescue LocalVoiceIdClient::Error => e
    render json: { error: e.message }, status: :service_unavailable
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

  def voice_payload
    JSON.parse(params[:voice_payload].presence || "{}")
  rescue JSON::ParserError
    {}
  end

  def voice_transcript
    params[:captured_voice_transcript].presence || params[:voice_transcript].to_s
  end

  def voice_id_samples
    raw_samples = params[:voice_id_samples]
    raw_samples = JSON.parse(raw_samples) if raw_samples.is_a?(String)
    Array(raw_samples).map do |sample|
      sample.respond_to?(:to_unsafe_h) ? sample.to_unsafe_h : sample.to_h
    end
  rescue JSON::ParserError, NoMethodError
    []
  end

  def return_to_path
    safe_return_path(params[:return_to])
  end

  def render_unlock_success(voice: false)
    @user.clear_typing_lock_failed_unlock!
    unlock_typing_session!
    if voice
      @voice_id_phrase = VoiceFingerprint::CANONICAL_PHRASE
      @voice_id_error = nil
      @voice_id_opening = true
      @voice_id_redirect_url = @return_to
      render :voice, status: :ok
      return
    end

    @unlock_result = :matched
    @unlock_redirect_url = @return_to
    @challenge_id ||= ""
    @challenge_text ||= ""
    render :new, status: :ok
  end

  def render_failed_unlock_cooldown(status:)
    failed_unlock = @user.active_typing_lock_failed_unlock
    return false unless failed_unlock

    @unlock_result = :missed
    @unlock_failure = failed_unlock
    @challenge_id = failed_unlock["challenge_id"].presence || @challenge_id || ""
    @challenge_text = ""
    render :new, status: status
    true
  end

  def render_next_security_lock_after(step)
    if step == :typing && @user.authenticator_app_enabled?
      @authenticator_challenge_token = begin_typing_authenticator_challenge!(@return_to)
      render :authenticator, status: :ok
    elsif @user.voice_id_enabled?
      render_voice_id_unlock(return_to: @return_to)
    else
      render_unlock_success
    end
  end
end
