class SettingsController < ApplicationController
  before_action :set_user

  def index
    @display_quote = @user.display_quote
    @display_contrast = @user.display_contrast
  end

  def display
    @display_quote = @user.display_quote
    @display_contrast = @user.display_contrast
  end

  def update_display
    if @user.update_display_quote(display_settings_params)
      redirect_to settings_display_path, notice: 'Display settings updated.'
    else
      @display_quote = @user.display_quote
      @display_contrast = @user.display_contrast
      flash.now[:alert] = 'Failed to update display settings.'
      render :display, status: :unprocessable_content
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
    load_security_settings
    load_database_encryption_status
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

  def local_agent
    load_local_agent_settings
  end

  def update_local_agent
    if @user.update_local_agent_settings(local_agent_params)
      LocalAgentSupervisorJob.perform_later(@user.id)
      redirect_to settings_local_agent_path, notice: "Local agent settings updated."
    else
      load_local_agent_settings
      flash.now[:alert] = "Failed to update local agent settings."
      render :local_agent, status: :unprocessable_content
    end
  end

  def run_local_agent_now
    unless @user.local_agent_enabled?
      redirect_to settings_local_agent_path, alert: "Enable the local agent before running a cycle."
      return
    end

    LocalAgentSupervisorJob.perform_later(@user.id, run_once: true)
    redirect_to settings_local_agent_path, notice: "Local agent cycle requested."
  end

  def approve_local_agent_recommendation
    recommendation = @user.agent_recommendations.pending.find(params[:id])

    if recommendation.approve!
      redirect_to settings_local_agent_path, notice: "Recommendation applied."
    else
      redirect_to settings_local_agent_path, alert: "Recommendation could not be applied."
    end
  end

  def dismiss_local_agent_recommendation
    recommendation = @user.agent_recommendations.pending.find(params[:id])
    recommendation.dismiss!
    redirect_to settings_local_agent_path, notice: "Recommendation dismissed."
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

  def encrypt_database
    passphrase_validation_error = database_encryption_passphrase_validation_error
    if passphrase_validation_error.present?
      redirect_to settings_security_path, alert: passphrase_validation_error
      return
    end

    passphrase = database_encryption_params[:passphrase].to_s.strip
    RecoverySecret.persist_user_passphrase!(passphrase)
    migrator = sqlcipher_database_migrator_for_passphrase(passphrase)

    disconnect_database_connections!
    results = migrator.migrate_configured!(env: Rails.env)

    redirect_with_database_encryption_results(results)
  rescue RecoverySecret::Missing
    redirect_to recovery_secret_path(return_to: settings_security_path), alert: "Enter the recovery passphrase before encrypting SQLite databases."
  rescue SqlcipherDatabaseMigrator::Error, SQLite3::Exception => e
    Rails.logger.error "Failed to encrypt SQLite databases from settings: #{e.message}"
    redirect_to settings_security_path, alert: "Failed to encrypt SQLite databases: #{e.message}"
  ensure
    reconnect_primary_database!
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
    @topologies = @user.topologies.ordered
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

    if @user.update_topology_settings(coerced) && update_topology_template_fields
      redirect_to settings_topologies_path, notice: 'Topology & graph settings updated.'
    else
      @topology_settings = @user.topology_settings
      @topologies = @user.topologies.ordered
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
    @topologies = @user.topologies.ordered
  end

  def github
    @github_settings = @user.github_settings
  end

  def update_github
    if @user.update_github_settings(github_params)
      redirect_to settings_github_path, notice: "GitHub settings updated."
    else
      @github_settings = @user.github_settings
      flash.now[:alert] = "Failed to update GitHub settings."
      render :github, status: :unprocessable_content
    end
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

  def load_security_settings
    @typing_lock_settings = @user.typing_lock_settings
    @authenticator_app_settings = @user.authenticator_app_settings
    @voice_id_settings = @user.voice_id_settings
    @authenticator_app_qr_svg = AuthenticatorApp.qr_svg(@user.authenticator_app_provisioning_uri) if @user.authenticator_app_configured?
  end

  def load_local_agent_settings
    @local_agent_settings = @user.local_agent_settings
    @local_agent_status = @user.local_agent_status
    @latest_agent_run = @user.agent_runs.recent.first
    @latest_agent_event = @user.agent_events.recent.first
    @pending_agent_recommendations = @user.agent_recommendations.pending.recent.limit(25)
    @recent_agent_events = @user.agent_events.recent.limit(20)
  end

  def load_database_encryption_status
    @database_recovery_passphrase_file_path = RecoverySecret.user_passphrase_file_path
    @database_encryption_results = sqlcipher_database_migrator.configured_statuses(env: Rails.env)
    @database_encryption_error = nil
    @database_encryption_requires_recovery_secret = false
  rescue RecoverySecret::Missing
    @database_encryption_results = []
    @database_encryption_error = nil
    @database_encryption_requires_recovery_secret = true
  rescue SqlcipherDatabaseMigrator::Error => e
    @database_encryption_results = []
    @database_encryption_error = e.message
    @database_encryption_requires_recovery_secret = false
  end

  def sqlcipher_database_migrator
    SqlcipherDatabaseMigrator.new(
      key_hex: RecoverySecret.present? ? RecoverySecret.sqlcipher_key_hex : ("0" * 64),
      backup_dir: sqlcipher_backup_dir
    )
  end

  def sqlcipher_database_migrator_for_passphrase(passphrase)
    SqlcipherDatabaseMigrator.new(
      key_hex: RecoverySecret.sqlcipher_key_hex_for(passphrase),
      backup_dir: sqlcipher_backup_dir
    )
  end

  def sqlcipher_backup_dir
    ENV["IDEA_FOUNDRY_SQLCIPHER_BACKUP_DIR"].presence || ENV["BACKUP_DIR"].presence
  end

  def disconnect_database_connections!
    ActiveRecord::Base.connection_handler.connection_pool_list.each(&:disconnect!)
  end

  def reconnect_primary_database!
    ActiveRecord::Base.establish_connection
    ActiveRecord::Base.connection
  rescue => e
    Rails.logger.warn "Could not reconnect the primary database after SQLCipher migration: #{e.message}"
  end

  def redirect_with_database_encryption_results(results)
    if results.empty?
      redirect_to settings_security_path, alert: "No SQLCipher-enabled SQLite databases are configured for #{Rails.env}."
      return
    end

    encrypted_count = results.count { |result| result.status == :encrypted }
    if encrypted_count.positive?
      backup_dirs = results.filter_map(&:backup_path).map { |path| File.dirname(path) }.uniq
      message = "Encrypted #{encrypted_count} SQLite #{'database'.pluralize(encrypted_count)}."
      message += " Plaintext backups: #{backup_dirs.to_sentence}." if backup_dirs.any?
      redirect_to settings_security_path, notice: message
    elsif results.all? { |result| result.status == :already_encrypted }
      redirect_to settings_security_path, notice: "SQLite databases are already encrypted."
    elsif results.all? { |result| result.status == :missing }
      redirect_to settings_security_path, notice: "Configured SQLite databases are missing; Rails will create them encrypted."
    else
      redirect_to settings_security_path, notice: "SQLite database encryption check finished."
    end
  end

  def scoring_params
    params.require(:scoring_weights).permit(:trl, :difficulty, :opportunity, :timing)
  end

  def email_params
    params.require(:email_settings).permit(:recipients)
  end

  def display_settings_params
    params.require(:display_settings).permit(:quote, :contrast)
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

  def database_encryption_params
    params.fetch(:database_encryption, {}).permit(:passphrase, :passphrase_confirmation, :saved_primary, :saved_secondary)
  end

  def database_encryption_passphrase_validation_error
    encryption_params = database_encryption_params
    passphrase = encryption_params[:passphrase].to_s.strip
    confirmation = encryption_params[:passphrase_confirmation].to_s.strip

    return "Enter a database recovery passphrase before encrypting SQLite databases." if passphrase.blank?
    return "Database recovery passphrase must be at least 16 characters long." if passphrase.length < 16
    passphrases_match = passphrase.bytesize == confirmation.bytesize && ActiveSupport::SecurityUtils.secure_compare(passphrase, confirmation)
    return "Passphrase confirmation does not match." unless passphrases_match

    saved_primary = ActiveModel::Type::Boolean.new.cast(encryption_params[:saved_primary])
    saved_secondary = ActiveModel::Type::Boolean.new.cast(encryption_params[:saved_secondary])
    return "Save the passphrase in more than one place before encrypting the database." unless saved_primary && saved_secondary

    nil
  end

  def idea_work_token_params
    params.fetch(:idea_work_tokens, {}).permit(:enabled)
  end

  def local_agent_params
    params.fetch(:local_agent, {}).permit(*User::ALLOWED_LOCAL_AGENT_SETTING_KEYS)
  end

  def github_params
    params.require(:github_settings).permit(:token, :clear_token, :api_base_url)
  end

  def update_topology_template_fields
    raw_fields = params[:topology_template_fields]
    return true if raw_fields.blank?

    field_sets = raw_fields.to_unsafe_h
    @user.topologies.where(id: field_sets.keys).all? do |topology|
      raw_for_topology = field_sets[topology.id.to_s] || {}
      fields = raw_for_topology.values
      topology.update(default_field_definitions: fields)
    end
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
