class SettingsController < ApplicationController
  before_action :set_user

  def index
    @display_quote = @user.display_quote
  end

  def update_display
    if @user.update_display_quote(display_settings_params)
      redirect_to settings_path, notice: 'Display quote updated.'
    else
      @display_quote = @user.display_quote
      flash.now[:alert] = 'Failed to update display quote.'
      render :index, status: :unprocessable_content
    end
  end

  def scoring
    # Scoring configuration page
  end

  def update_scoring
    weights = scoring_params
    
    # Validate weights are numeric and within reasonable bounds
    if valid_scoring_weights?(weights)
      @user.update_scoring_weights(weights)
      
      # Recalculate all idea scores with new weights
      recalculate_all_scores
      
      respond_to do |format|
        format.html { redirect_to settings_scoring_path, notice: 'Scoring weights updated successfully. All idea scores have been recalculated.' }
        format.json { 
          render json: { 
            success: true, 
            weights: @user.scoring_weights,
            message: 'Scoring weights updated successfully'
          }
        }
      end
    else
      respond_to do |format|
        format.html { 
          flash.now[:alert] = 'Invalid scoring weights. Please ensure all values are numbers between -1 and 1.'
          render :scoring, status: :unprocessable_content 
        }
        format.json { 
          render json: { 
            success: false, 
            errors: ['Invalid scoring weights. Please ensure all values are numbers between -1 and 1.']
          }, status: :unprocessable_content 
        }
      end
    end
  end

  def get_scoring_weights
    respond_to do |format|
      format.json {
        render json: {
          weights: @user.scoring_weights,
          formula: @user.scoring_formula_display
        }
      }
    end
  end

  def email
    @email_settings = @user.email_settings
    @notification_triggers = @user.notification_triggers
    @notification_content = @user.notification_content
    @notification_templates = @user.notification_templates
    @event_presets = @user.event_presets
    @available_presets = EmailPresetHelper::PRESETS
    @available_themes = EmailPresetHelper::PRESETS
    @inbound_address = Rails.application.credentials.dig(:resend, :inbound_address)
    @sha3_key = Rails.application.credentials.dig(:email_ingestion, :sha3_key)
  end

  def security
    @typing_lock_settings = @user.typing_lock_settings
    @authenticator_app_settings = @user.authenticator_app_settings
    @voice_id_settings = @user.voice_id_settings
    @authenticator_app_qr_svg = AuthenticatorApp.qr_svg(@user.authenticator_app_provisioning_uri) if @user.authenticator_app_configured?
  end

  def idea_work_tokens
    @idea_work_token_settings = @user.idea_work_token_settings
  end

  def update_idea_work_tokens
    if @user.update_idea_work_token_settings(idea_work_token_params)
      redirect_to settings_idea_work_tokens_path, notice: "Idea work token settings updated."
    else
      @idea_work_token_settings = @user.idea_work_token_settings
      flash.now[:alert] = "Failed to update idea work token settings."
      render :idea_work_tokens, status: :unprocessable_content
    end
  end

  def update_security
    was_voice_id_configured = @user.voice_id_configured?
    typing_lock_updated = @user.update_typing_lock_settings(typing_lock_params)
    authenticator_app_updated = @user.update_authenticator_app_settings(authenticator_app_params)
    voice_id_updated = @user.update_voice_id_settings(voice_id_params)

    if typing_lock_updated && authenticator_app_updated && voice_id_updated
      if @user.security_lock_enabled?
        unlock_typing_session!
      else
        expire_typing_session!
      end

      if @user.voice_id_requested? && !was_voice_id_configured && !@user.voice_id_configured?
        enrollment_url = enroll_voice_id_path(return_to: settings_security_path)
        respond_to do |format|
          format.html { redirect_to enrollment_url, notice: "Say the Voice ID phrase three times to finish setup." }
          format.json { render json: { saved: true, redirect_to: enrollment_url } }
        end
      else
        respond_to do |format|
          format.html { redirect_to settings_security_path, notice: "Security settings updated." }
          format.json { render json: { saved: true } }
        end
      end
    else
      @typing_lock_settings = @user.typing_lock_settings
      @authenticator_app_settings = @user.authenticator_app_settings
      @voice_id_settings = @user.voice_id_settings
      @authenticator_app_qr_svg = AuthenticatorApp.qr_svg(@user.authenticator_app_provisioning_uri) if @user.authenticator_app_configured?
      respond_to do |format|
        format.html do
          flash.now[:alert] = "Failed to update security settings."
          render :security, status: :unprocessable_content
        end
        format.json { render json: { saved: false }, status: :unprocessable_entity }
      end
    end
  end

  def update_notifications
    triggers = params[:notification_triggers] || []
    content = params[:notification_content]&.permit!&.to_h || {}
    templates = params[:notification_templates]&.permit!&.to_h || {}
    presets = params[:event_presets]&.permit!&.to_h || {}
    recipients = params.dig(:email_settings, :recipients)

    @user.update_email_settings({ 'recipients' => recipients.to_s }) if recipients.present? || params.key?(:email_settings)
    @user.update_notification_triggers(triggers)
    @user.update_notification_content(content)
    @user.update_notification_templates(templates)
    @user.update_event_presets(presets)

    redirect_to settings_email_path, notice: "Email & notification preferences updated."
  end

  def topologies
    @topology_settings = @user.topology_settings
  end

  def lists
    @list_settings = @user.list_settings
  end

  def update_lists
    raw = params.require(:list_settings).permit(*User::ALLOWED_LIST_SETTING_KEYS)

    if @user.update_list_settings(raw)
      redirect_to settings_lists_path, notice: 'List settings updated.'
    else
      @list_settings = @user.list_settings
      flash.now[:alert] = 'Failed to update list settings.'
      render :lists, status: :unprocessable_content
    end
  end

  def update_topologies
    raw = params.require(:topology_settings).permit(*User::ALLOWED_TOPOLOGY_SETTING_KEYS)
    coerced = raw.to_h.each_with_object({}) do |(k, v), h|
      default = User::DEFAULT_TOPOLOGY_SETTINGS[k]
      h[k] = case default
              when true, false then ActiveModel::Type::Boolean.new.cast(v)
              when Integer then v.to_i
              when Float then v.to_f
              else v.to_s
              end
    end

    if @user.update_topology_settings(coerced)
      redirect_to settings_topologies_path, notice: 'Topology & graph settings updated.'
    else
      @topology_settings = @user.topology_settings
      flash.now[:alert] = 'Failed to update settings.'
      render :topologies, status: :unprocessable_content
    end
  end

  def idea_tabs
    @idea_tab_settings = @user.idea_tab_settings
  end

  def update_idea_tabs
    raw = if params[:reset_idea_tabs].present?
            User::DEFAULT_IDEA_TAB_SETTINGS
          else
            params[:idea_tabs]&.permit!&.to_h || {}
          end

    if @user.update_idea_tab_settings(raw)
      respond_to do |format|
        format.html { redirect_to settings_idea_tabs_path, notice: 'Idea tab visibility updated.' }
        format.json { render json: { saved: true } }
      end
    else
      @idea_tab_settings = @user.idea_tab_settings
      respond_to do |format|
        format.html do
          flash.now[:alert] = 'Failed to update idea tab settings.'
          render :idea_tabs, status: :unprocessable_content
        end
        format.json { render json: { saved: false }, status: :unprocessable_entity }
      end
    end
  end

  def templates
    @templates = @user.templates.order(:name)
    @default_template = @templates.find_by(is_default: true)
  end

  def exports
    @export_jobs = @user.export_jobs.recent.limit(20)
    @active_export = @user.export_jobs.exports.where(status: [:pending, :processing]).first
    @active_backup = @user.export_jobs.backups.where(status: [:pending, :processing]).first
    @last_backup = @user.export_jobs.backups.where(status: :completed).order(created_at: :desc).first
    @backup_settings = @user.backup_settings
  end

  def create_export
    active_export = @user.export_jobs.exports.where(status: [:pending, :processing]).first
    if active_export
      redirect_to settings_exports_path, alert: "An export is already in progress."
      return
    end

    password = params[:password].presence

    if password.present? && password.length < 8
      redirect_to settings_exports_path, alert: "Password must be at least 8 characters long."
      return
    end

    @export_job = @user.export_jobs.create!(kind: :export)
    @export_job.start_export!(password)

    redirect_to settings_exports_path, notice: "Export queued. A worker will process it shortly."
  rescue => e
    Rails.logger.error "Failed to start export: #{e.message}"
    redirect_to settings_exports_path, alert: "Failed to start export: #{e.message}"
  end

  def create_backup
    active_backup = @user.export_jobs.backups.where(status: [:pending, :processing]).first
    if active_backup
      redirect_to settings_exports_path, alert: "A backup is already in progress."
      return
    end

    @export_job = @user.export_jobs.create!(kind: :backup)
    @export_job.start_export!

    redirect_to settings_exports_path, notice: "Backup queued. A worker will process it shortly."
  rescue => e
    Rails.logger.error "Failed to start backup: #{e.message}"
    redirect_to settings_exports_path, alert: "Failed to start backup: #{e.message}"
  end

  def download_export
    @export_job = @user.export_jobs.find(params[:id])

    unless @export_job.completed? && @export_job.file_exists?
      redirect_to settings_exports_path, alert: "Export file is not available for download."
      return
    end

    send_file @export_job.file_path,
              filename: @export_job.download_filename,
              type: @export_job.password_protected? ? 'application/zip' : 'application/gzip',
              disposition: 'attachment'
  end

  def destroy_export
    @export_job = @user.export_jobs.find(params[:id])
    @export_job.cleanup_file! if @export_job.file_exists?
    @export_job.destroy!

    redirect_to settings_exports_path, notice: "Export deleted successfully."
  end

  def cleanup_exports
    old_exports = @user.export_jobs.where('created_at < ?', 7.days.ago)

    cleanup_count = 0
    old_exports.each do |export_job|
      export_job.cleanup_file! if export_job.file_exists?
      export_job.destroy!
      cleanup_count += 1
    end

    redirect_to settings_exports_path, notice: "Cleaned up #{cleanup_count} old exports."
  end

  def update_backup
    backup_params = params.require(:backup_settings).permit(
      :frequency, :retention_days, :max_backups, :auto_cleanup, :email_notification
    )

    if @user.update_backup_settings(backup_params)
      redirect_to settings_exports_path, notice: "Backup settings updated."
    else
      redirect_to settings_exports_path, alert: "Failed to update backup settings."
    end
  end

  def kb
    @kb_folders = @user.kb_folders
  end

  def update_kb
    paths = Array(params[:kb_folders]).reject(&:blank?)
    if @user.update_kb_folders(paths)
      redirect_to settings_kb_path, notice: "KB folders updated."
    else
      @kb_folders = paths
      flash.now[:alert] = "Failed to update KB folders."
      render :kb, status: :unprocessable_content
    end
  end

  def api_keys
    @api_keys = @user.api_keys.order(created_at: :desc)
  end

  def create_api_key
    key = ApiKey.generate(user: @user, name: params[:name])
    flash[:api_token] = key.raw_token
    redirect_to settings_api_keys_path, notice: "API key created."
  rescue => e
    redirect_to settings_api_keys_path, alert: "Failed to create key: #{e.message}"
  end

  def destroy_api_key
    key = @user.api_keys.find(params[:id])
    key.destroy!
    redirect_to settings_api_keys_path, notice: "API key deleted."
  end

  private

  def scoring_params
    params.require(:scoring_weights).permit(:trl, :difficulty, :opportunity, :timing)
  end

  def email_params
    params.require(:email_settings).permit(:recipients)
  end

  def display_settings_params
    params.require(:display_settings).permit(:quote)
  end

  def typing_lock_params
    params.require(:typing_lock).permit(:enabled, :lock_after_minutes, :failed_unlock_cooldown_minutes)
  end

  def authenticator_app_params
    params.fetch(:authenticator_app, {}).permit(:enabled)
  end

  def voice_id_params
    params.fetch(:voice_id, {}).permit(:enabled)
  end

  def idea_work_token_params
    params.fetch(:idea_work_tokens, {}).permit(:enabled)
  end

  def valid_scoring_weights?(weights)
    weights.values.all? do |weight|
      weight.present? && 
      weight.to_f.between?(-1.0, 1.0) && 
      weight.to_f.to_s == weight.to_f.round(2).to_s
    end
  end

  def recalculate_all_scores
    @user.ideas.find_each do |idea|
      idea.send(:calculate_score)
      idea.save! if idea.changed?
    end
  end
end
