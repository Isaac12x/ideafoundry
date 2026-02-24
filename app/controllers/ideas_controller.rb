class IdeasController < ApplicationController
  before_action :set_user
  before_action :set_idea, only: [:show, :edit, :update, :destroy, :send_email, :approve_pending_email, :discard_pending_email]
  before_action :check_cool_off_period, only: [:edit, :update]

  def index
    @ideas = @user.ideas.includes(:lists, :idea_lists, :topologies)
    
    # Apply filters
    @ideas = apply_filters(@ideas)
    
    # Apply sorting
    @ideas = apply_sorting(@ideas)
    
    @ideas = @ideas.page(params[:page]).per(20)
  end

  def show
    # Detailed view of a single idea
  end

  def new
    @idea = @user.ideas.build
    @lists = @user.lists.ordered
    @topologies = @user.topologies.ordered
    @templates = @user.templates.order(:name)

    # User picks template in step 1 of the form
  end

  def create
    @idea = @user.ideas.build(idea_params)
    
    if @idea.save
      @idea.create_version("Initial version")

      # Add to selected lists if provided
      if params[:list_ids].present?
        params[:list_ids].reject(&:blank?).each do |list_id|
          list = @user.lists.find(list_id)
          @idea.idea_lists.create(list: list)
        end
      end

      redirect_to @idea, notice: 'Idea was successfully created.'
    else
      @lists = @user.lists.ordered
      @topologies = @user.topologies.ordered
      @templates = @user.templates.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @lists = @user.lists.ordered
    @topologies = @user.topologies.ordered
    @templates = @user.templates.order(:name)
  end

  def update
    respond_to do |format|
      if @idea.update(idea_params)
        @idea.create_version(version_commit_message)

        # Update list associations if provided (only for non-AJAX requests)
        if params[:list_ids] && !request.xhr?
          current_list_ids = @idea.lists.pluck(:id)
          new_list_ids = params[:list_ids].reject(&:blank?).map(&:to_i)
          
          # Remove from lists that are no longer selected
          (current_list_ids - new_list_ids).each do |list_id|
            @idea.idea_lists.find_by(list_id: list_id)&.destroy
          end
          
          # Add to new lists
          (new_list_ids - current_list_ids).each do |list_id|
            list = @user.lists.find(list_id)
            @idea.idea_lists.create(list: list)
          end
        end
        
        format.html { redirect_to @idea, notice: 'Idea was successfully updated.' }
        format.json { 
          render json: { 
            success: true, 
            computed_score: @idea.computed_score,
            message: 'Score updated successfully'
          }
        }
      else
        format.html {
          @lists = @user.lists.ordered
          @topologies = @user.topologies.ordered
          @templates = @user.templates.order(:name)
          render :edit, status: :unprocessable_entity
        }
        format.json { 
          render json: { 
            success: false, 
            errors: @idea.errors.full_messages 
          }, status: :unprocessable_entity 
        }
      end
    end
  end

  def send_email
    recipients = params[:recipients].to_s.split(',').map(&:strip).reject(&:blank?)
    recipients = @user.email_recipients if recipients.empty?

    if recipients.empty?
      redirect_to @idea, alert: 'No recipients configured. Add recipients in Settings > Email or enter an address.'
      return
    end

    recipients.each do |email|
      IdeaMailer.share_idea(@idea, email).deliver_later
    end

    redirect_to @idea, notice: "Idea emailed to #{recipients.join(', ')}."
  end

  def approve_pending_email
    pending = @idea.metadata&.dig("pending_emails") || []
    idx = params[:email_index].to_i
    email_data = pending[idx]

    unless email_data
      redirect_to @idea, alert: "Pending email not found."
      return
    end

    current_description = @idea.description.to_plain_text
    @idea.description = "#{current_description}\n\n---\n\n#{email_data['body']}"
    @idea.metadata["pending_emails"].delete_at(idx)
    @idea.save!
    @idea.compute_integrity_hash!

    redirect_to @idea, notice: "Email merged into idea."
  end

  def discard_pending_email
    pending = @idea.metadata&.dig("pending_emails") || []
    idx = params[:email_index].to_i

    unless pending[idx]
      redirect_to @idea, alert: "Pending email not found."
      return
    end

    @idea.metadata["pending_emails"].delete_at(idx)
    @idea.save!

    redirect_to @idea, notice: "Pending email discarded."
  end

  def destroy
    @idea.destroy
    redirect_to ideas_path, notice: 'Idea was successfully deleted.'
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:id])
  end

  def check_cool_off_period
    if @idea.in_cool_off? && !@idea.can_edit_content?
      redirect_to @idea, alert: "This idea is in a cool-off period until #{@idea.cool_off_until.strftime('%B %d, %Y at %I:%M %p')}. You can only edit notes during this time."
    end
  end

  def version_commit_message
    changes = @idea.previous_changes
    scoring_fields = %w[trl difficulty opportunity timing]
    changed_scores = scoring_fields.select { |f| changes.key?(f) }

    if changes.key?("state")
      "State changed to #{@idea.state.humanize}"
    elsif changed_scores.any? && (changes.keys - scoring_fields - %w[computed_score updated_at]).empty?
      deltas = changed_scores.map { |f| "#{f}: #{changes[f][0]} → #{changes[f][1]}" }
      "Score update (#{deltas.join(', ')})"
    elsif changes.key?("title")
      "Updated title and details"
    else
      "Updated idea"
    end
  end

  def idea_params
    params.require(:idea).permit(
      :title, :state, :template_id,
      :trl, :difficulty, :opportunity, :timing,
      :difficulty_explanation, :opportunity_explanation, :timing_explanation,
      :description,
      :hero_image,
      attachments: [],
      topology_ids: [],
      metadata: {}
    )
  end

  def apply_filters(ideas)
    # Filter by state
    if params[:state].present? && params[:state] != 'all'
      ideas = ideas.by_state(params[:state])
    end
    
    # Filter by TRL range
    if params[:trl_min].present? || params[:trl_max].present?
      trl_min = params[:trl_min].presence || 0
      trl_max = params[:trl_max].presence || 10
      ideas = ideas.where(trl: trl_min..trl_max)
    end
    
    # Filter by score range
    if params[:score_min].present? || params[:score_max].present?
      score_min = params[:score_min].presence || -10
      score_max = params[:score_max].presence || 10
      ideas = ideas.by_score_range(score_min, score_max)
    end
    
    # Filter by topology
    if params[:topology_id].present? && params[:topology_id] != 'all'
      ideas = ideas.joins(:idea_topologies).where(idea_topologies: { topology_id: params[:topology_id] })
    end
    
    # Filter by list
    if params[:list_id].present? && params[:list_id] != 'all'
      ideas = ideas.joins(:idea_lists).where(idea_lists: { list_id: params[:list_id] })
    end
    
    # Filter by date range
    if params[:created_after].present?
      ideas = ideas.where('created_at >= ?', params[:created_after])
    end
    
    if params[:created_before].present?
      ideas = ideas.where('created_at <= ?', params[:created_before])
    end
    
    # Filter by attachments
    if params[:has_attachments] == 'true'
      ideas = ideas.joins(:attachments_attachments)
    elsif params[:has_attachments] == 'false'
      ideas = ideas.left_joins(:attachments_attachments).where(active_storage_attachments: { id: nil })
    end
    
    ideas
  end

  def apply_sorting(ideas)
    sort_by = params[:sort_by] || 'created_at'
    sort_order = params[:sort_order] || 'desc'
    
    case sort_by
    when 'title'
      ideas.order(title: sort_order)
    when 'state'
      ideas.order(state: sort_order)
    when 'score'
      ideas.order(computed_score: sort_order)
    when 'trl'
      ideas.order(trl: sort_order)
    when 'created_at'
      ideas.order(created_at: sort_order)
    when 'updated_at'
      ideas.order(updated_at: sort_order)
    else
      ideas.order(created_at: sort_order)
    end
  end
end
