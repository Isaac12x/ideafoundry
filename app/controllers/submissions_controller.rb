class SubmissionsController < ApplicationController
  before_action :set_user
  before_action :set_submission, only: [:show, :approve, :reject, :reopen, :destroy]

  def index
    @status_counts = {
      pending: @user.submissions.pending.count,
      approved: @user.submissions.approved.count,
      rejected: @user.submissions.rejected.count
    }

    @submissions = @user.submissions.includes(:idea).with_attached_files
    @submissions = @submissions.where(status: params[:status]) if params[:status].present? && params[:status] != "all"
    @submissions = @submissions.by_source(params[:source]) if params[:source].present?
    @submissions = @submissions.by_priority(params[:priority]) if params[:priority].present?
    @submissions = @submissions.where(status: :pending) unless params[:status].present?
    @submissions = @submissions.recent
  end

  def show
    @topologies = @user.topologies.ordered
    @lists = @user.lists.ordered
  end

  def approve
    approver = SubmissionApprover.new(@submission)
    idea = approver.approve!(approve_params)
    redirect_to idea, notice: "Submission approved and idea created."
  rescue => e
    redirect_to @submission, alert: "Approval failed: #{e.message}"
  end

  def reject
    @submission.reject!(params[:review_notes])
    redirect_to submissions_path, notice: "Submission rejected."
  end

  def reopen
    @submission.reopen!
    redirect_to submissions_path, notice: "Submission reopened."
  end

  def destroy
    @submission.destroy!
    redirect_to submissions_path, notice: "Submission deleted."
  end

  private

  def set_submission
    @submission = @user.submissions.find(params[:id])
  end

  def approve_params
    params.permit(
      :title, :trl, :difficulty, :opportunity, :timing,
      :list_id, topology_ids: []
    ).to_h.symbolize_keys
  end
end
