class VersionsController < ApplicationController
  before_action :set_idea
  before_action :set_version, only: [:show, :restore]
  before_action :set_comparison_versions, only: [:compare]

  # GET /ideas/:idea_id/versions
  def index
    @versions = @idea.versions.chronological
    @version_service = VersionService.new(@idea)
    @timeline = @version_service.timeline
  end

  # GET /ideas/:idea_id/versions/:id
  def show
    @parent_version = @version.parent_version
    @child_versions = @version.child_versions
    @diff = @parent_version ? @version.diff_with(@parent_version) : {}
  end

  # GET /ideas/:idea_id/versions/compare?from=:from_id&to=:to_id
  def compare
    @version_service = VersionService.new(@idea)
    @diff = @version_service.compare_versions(@from_version, @to_version)
  end

  # POST /ideas/:idea_id/versions/:id/restore
  def restore
    @version_service = VersionService.new(@idea)
    
    if @version_service.restore_version(@version)
      redirect_to idea_path(@idea), notice: "Version restored successfully. A new version has been created."
    else
      redirect_to idea_versions_path(@idea), alert: "Failed to restore version."
    end
  rescue => e
    redirect_to idea_versions_path(@idea), alert: "Error restoring version: #{e.message}"
  end

  private

  def set_idea
    @idea = Idea.find(params[:idea_id])
  end

  def set_version
    @version = @idea.versions.find(params[:id])
  end

  def set_comparison_versions
    @from_version = @idea.versions.find(params[:from])
    @to_version = @idea.versions.find(params[:to])
  rescue ActiveRecord::RecordNotFound
    redirect_to idea_versions_path(@idea), alert: "Invalid version comparison."
  end
end
