class SettingsController < ApplicationController
  before_action :set_user

  def index
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
          render :scoring, status: :unprocessable_entity 
        }
        format.json { 
          render json: { 
            success: false, 
            errors: ['Invalid scoring weights. Please ensure all values are numbers between -1 and 1.']
          }, status: :unprocessable_entity 
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
      render :topologies, status: :unprocessable_entity
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

  private

  def scoring_params
    params.require(:scoring_weights).permit(:trl, :difficulty, :opportunity, :timing)
  end

  def email_params
    params.require(:email_settings).permit(:recipients)
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