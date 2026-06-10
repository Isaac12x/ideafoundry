class SubmissionApprover
  attr_reader :submission, :idea

  def initialize(submission)
    @submission = submission
  end

  def approve!(params = {})
    raise "Submission is not pending" unless submission.pending?

    ActiveRecord::Base.transaction do
      @idea = build_idea(params)
      @idea.save!
      @idea.create_version("Created from submission ##{submission.id}")

      copy_attachments
      assign_topology(params[:topology_ids]) if params[:topology_ids].present?
      assign_list(params[:list_id]) if params[:list_id].present?

      submission.update!(
        status: :approved,
        idea_id: @idea.id,
        reviewed_at: Time.current
      )
    end

    @idea
  end

  private

  def build_idea(params)
    submission.user.ideas.build(
      title: params[:title].presence || submission.title,
      state: :idea_new,
      description: submission.processed_body.present? ? submission.processed_body.to_s : submission.body,
      trl: params[:trl]&.to_i,
      difficulty: params[:difficulty]&.to_i,
      opportunity: params[:opportunity]&.to_i,
      timing: params[:timing]&.to_i,
      metadata: {
        "submission_source" => submission.source,
        "submission_id" => submission.id,
        "submission_reference" => submission.temporary_idea_id,
        "submission_references" => [submission.temporary_idea_id]
      }
    )
  end

  def copy_attachments
    submission.files.each do |file|
      @idea.attachments.attach(file.blob)
    end
  end

  def assign_topology(topology_ids)
    Array(topology_ids).each do |tid|
      topology = submission.user.topologies.find_by(id: tid)
      @idea.idea_topologies.create!(topology: topology) if topology
    end
  end

  def assign_list(list_id)
    list = submission.user.lists.find_by(id: list_id)
    @idea.idea_lists.create!(list: list) if list
  end
end
