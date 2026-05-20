class RecoverySecretsController < ApplicationController
  skip_before_action :set_user
  skip_before_action :require_database_recovery_unlock
  skip_before_action :require_typing_unlock

  def new
    @return_to = safe_return_path(params[:return_to])
  end

  def create
    @return_to = safe_return_path(params[:return_to])
    passphrase = params[:recovery_passphrase].to_s

    if passphrase.blank?
      @recovery_secret_error = "Enter the recovery passphrase to continue."
      render :new, status: :unprocessable_content
      return
    end

    reset_recovery_secret_database_connections! if database_recovery_unlock_required?
    RecoverySecret.with(passphrase, override_configured: true) { verify_recovery_secret! }
    RecoverySecret.persist_user_passphrase!(passphrase)
    session[RECOVERY_SECRET_SESSION_KEY] = passphrase
    redirect_to @return_to
  rescue ActiveRecord::StatementInvalid, ActiveSupport::MessageEncryptor::InvalidMessage, SQLite3::Exception => e
    reset_recovery_secret_database_connections!
    Rails.logger.warn "Recovery passphrase did not unlock encrypted data: #{e.class}: #{e.message}"
    @recovery_secret_error = "That recovery passphrase did not unlock the encrypted data."
    render :new, status: :unprocessable_content
  end

  def destroy
    session.delete(RECOVERY_SECRET_SESSION_KEY)
    reset_recovery_secret_database_connections!
    redirect_to recovery_secret_path, notice: "Recovery passphrase cleared."
  end

  private

  def verify_recovery_secret!
    User.first&.security_lock_enabled?
    true
  end

  def database_recovery_unlock_required?
    SqlcipherDatabaseMigrator.locked_database_paths_without_recovery_secret(env: Rails.env).present?
  end

  def reset_recovery_secret_database_connections!
    ActiveRecord::Base.connection_handler.connection_pool_list.each(&:disconnect!)
  end
end
