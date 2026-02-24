class ExportsController < ApplicationController
  before_action :set_user
  before_action :set_export_job, only: [:show, :download, :destroy]

  def index
    @export_jobs = @user.export_jobs.recent.limit(20)
    @active_export = @user.export_jobs.where(status: [:pending, :processing]).first
  end

  def show
    respond_to do |format|
      format.json do
        render json: {
          id: @export_job.id,
          status: @export_job.status,
          progress: @export_job.progress,
          error_message: @export_job.error_message,
          file_size: @export_job.file_size_human,
          duration: @export_job.duration_human,
          download_url: @export_job.completed? ? download_export_path(@export_job) : nil
        }
      end
      format.html
    end
  end

  def create
    # Check if there's already an active export
    active_export = @user.export_jobs.where(status: [:pending, :processing]).first
    if active_export
      redirect_to exports_path, alert: "An export is already in progress. Please wait for it to complete."
      return
    end

    password = params[:password].presence
    
    # Validate password if provided
    if password.present? && password.length < 8
      redirect_to exports_path, alert: "Password must be at least 8 characters long."
      return
    end

    @export_job = @user.export_jobs.create!
    @export_job.start_export!(password)

    respond_to do |format|
      format.html { redirect_to exports_path, notice: "Export started successfully." }
      format.json { render json: { id: @export_job.id, status: @export_job.status } }
    end
  rescue => e
    Rails.logger.error "Failed to start export: #{e.message}"
    respond_to do |format|
      format.html { redirect_to exports_path, alert: "Failed to start export: #{e.message}" }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
    end
  end

  def download
    unless @export_job.completed? && @export_job.file_exists?
      redirect_to exports_path, alert: "Export file is not available for download."
      return
    end

    send_file @export_job.file_path,
              filename: @export_job.download_filename,
              type: @export_job.password_protected? ? 'application/zip' : 'application/gzip',
              disposition: 'attachment'
  end

  def destroy
    if @export_job.file_exists?
      @export_job.cleanup_file!
    end
    
    @export_job.destroy!
    
    respond_to do |format|
      format.html { redirect_to exports_path, notice: "Export deleted successfully." }
      format.json { head :no_content }
    end
  end

  def cleanup_old
    # Clean up exports older than 7 days
    old_exports = @user.export_jobs.where('created_at < ?', 7.days.ago)
    
    cleanup_count = 0
    old_exports.each do |export_job|
      export_job.cleanup_file! if export_job.file_exists?
      export_job.destroy!
      cleanup_count += 1
    end

    respond_to do |format|
      format.html { redirect_to exports_path, notice: "Cleaned up #{cleanup_count} old exports." }
      format.json { render json: { cleaned_up: cleanup_count } }
    end
  end

  private

  def set_export_job
    @export_job = @user.export_jobs.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_to exports_path, alert: "Export not found." }
      format.json { render json: { error: "Export not found" }, status: :not_found }
    end
  end
end