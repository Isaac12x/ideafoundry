class IdeasController < ApplicationController
  before_action :set_user
  before_action :set_idea, only: [:show, :edit, :update, :destroy, :send_email, :approve_pending_email, :discard_pending_email, :enrich, :enrichment_status, :archive, :restore, :add_to_list, :create_version, :make_primary]
  before_action :check_cool_off_period, only: [:edit, :update]

  def index
    @ideas = @user.ideas.non_draft.primary_or_standalone.includes(:lists, :idea_lists, :topologies, :idea_entries)
    @user.default_kanban_board if @user.kanban_boards.none?
    @kanban_boards = @user.kanban_boards.ordered.includes(:lists)
    @named_lists = @user.lists.named.ordered

    @ideas = apply_filters(@ideas)
    @ideas = apply_sorting(@ideas)
    @ideas = @ideas.page(params[:page]).per(20)

    respond_to do |format|
      format.html
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.append("ideas-grid", partial: "ideas/ideas_batch", locals: { ideas: @ideas }),
          turbo_stream.replace("infinite-scroll-sentinel", partial: "ideas/infinite_scroll_sentinel", locals: { ideas: @ideas })
        ]
      end
    end
  end

  def show
    @inline_agent_recommendations = @user.agent_recommendations.pending.where(target: @idea).recent.limit(8)
  end

  def new
    # Auto-draft: create a hidden draft idea immediately so drawings can attach
    # to it during composition. Drafts are filtered from listings and cleaned up
    # daily by CleanOrphanedDraftsJob if abandoned.
    @idea = @user.ideas.create!(draft: true, state: :idea_new, attempt_count: 0, title: "")
    redirect_to edit_idea_path(@idea, draft: 1)
  end

  def create
    @idea = @user.ideas.build(idea_params)

    if @idea.save
      @idea.create_version("Initial version")
      @idea.enqueue_attachment_ocr!

      redirect_to uncompleted_ideas_path(idea_draft_saved: 1), notice: 'Idea was successfully created.'
    else
      load_form_options
      render :new, status: :unprocessable_content
    end
  end

  def edit
    load_form_options
  end

  def update
    was_draft = @idea.draft?
    attrs = idea_params
    attrs[:draft] = false if was_draft  # Submitting promotes draft → real idea
    respond_to do |format|
      if @idea.update(attrs)
        if !request.xhr? && !was_draft && kanban_assignment_requested? && selected_kanban_list_requested? && !@idea.kanban_eligible?
          @idea.errors.add(:base, @idea.kanban_ineligibility_message)
          load_form_options
          format.html { render :edit, status: :unprocessable_content }
          format.json { render json: { success: false, errors: @idea.errors.full_messages }, status: :unprocessable_content }
          return
        end

        @idea.create_version(was_draft ? "Initial version" : version_commit_message)
        @idea.enqueue_attachment_ocr!

        # Update list association if provided (only for non-AJAX requests)
        unless request.xhr? || was_draft
          update_kanban_list_memberships if params.key?(:kanban_list_ids) || params.key?(:list_id)
          update_named_list_memberships if params.key?(:named_list_ids)
        end
        
        format.html do
          redirect_to(
            was_draft ? uncompleted_ideas_path(idea_draft_saved: 1) : idea_path(@idea, idea_edit_saved: 1),
            notice: 'Idea was successfully updated.'
          )
        end
        format.json { 
          render json: { 
            success: true, 
            computed_score: @idea.computed_score,
            message: 'Score updated successfully'
          }
        }
      else
        format.html {
          load_form_options
          render :edit, status: :unprocessable_content
        }
        format.json { 
          render json: { 
            success: false, 
            errors: @idea.errors.full_messages 
          }, status: :unprocessable_content 
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

  # POST /ideas/:id/enrich
  # Triggers web enrichment for this idea.
  def enrich
    query = params[:query].presence
    sources = params[:sources].presence&.split(",")

    IdeaEnrichmentJob.perform_later(@idea.id, query: query, sources: sources)

    respond_to do |format|
      format.html { redirect_to @idea, notice: 'Enrichment started. Results will appear in the Enrichment tab when ready.' }
      format.json { render json: { status: 'enqueued', idea_id: @idea.id } }
    end
  end

  # GET /ideas/:id/enrichment_status
  # Returns the current enrichment state as JSON.
  def enrichment_status
    service = IdeaEnrichmentService.new(@idea)
    enrichment = service.last_enrichment

    render json: {
      idea_id: @idea.id,
      enriched: service.enriched?,
      enrichment: enrichment,
      can_enrich: !service.enriched?
    }
  end

  # GET /ideas/archived
  # Shows all archived (soft-deleted) ideas.
  def archived
    @ideas = @user.ideas.non_draft.where.not(discarded_at: nil)
                  .order(discarded_at: :desc)
                  .page(params[:page]).per(20)
  end

  # GET /ideas/uncompleted
  # Gives users a calm place to resume abandoned auto-drafts and the idea they
  # just started instead of interrupting the composition flow immediately.
  def uncompleted
    recent_cutoff = 15.minutes.ago
    @draft_ideas = @user.ideas.drafts.where(discarded_at: nil).order(updated_at: :desc)
    @recent_ideas = @user.ideas.non_draft
                         .where(discarded_at: nil)
                         .where("ideas.updated_at >= ?", recent_cutoff)
                         .order(updated_at: :desc)
  end

  # POST /ideas/:id/archive
  # Soft-deletes an idea (archive).
  def archive
    @idea.update!(discarded_at: Time.current)

    respond_to do |format|
      format.html { redirect_to ideas_path, notice: 'Idea archived.' }
      format.json { render json: { success: true, discarded_at: @idea.discarded_at } }
    end
  end

  # POST /ideas/:id/restore
  # Restores an archived idea.
  def restore
    @idea.update!(discarded_at: nil)

    respond_to do |format|
      format.html { redirect_to @idea, notice: 'Idea restored.' }
      format.json { render json: { success: true, discarded_at: nil } }
    end
  end

  def add_to_list
    list = @user.lists.find(params[:list_id])
    result = add_idea_to_list(@idea, list)

    respond_to do |format|
      format.html do
        redirect_back fallback_location: ideas_path, notice: "Idea added to #{list.name}."
      end
      format.json do
        render json: idea_list_membership_payload(@idea, list, result)
      end
    end
  rescue ActiveRecord::RecordNotFound
    respond_to do |format|
      format.html { redirect_back fallback_location: ideas_path, alert: "List not found." }
      format.json { render json: { error: "List not found." }, status: :not_found }
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.html { redirect_back fallback_location: ideas_path, alert: e.record.errors.full_messages.to_sentence }
      format.json { render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_content }
    end
  end

  # POST /ideas/:id/create_version
  def create_version
    copy = @idea.create_new_version!
    redirect_to idea_path(copy), notice: "Created v#{copy.version_number}."
  rescue => e
    redirect_to idea_path(@idea), alert: "Could not create version: #{e.message}"
  end

  # POST /ideas/:id/make_primary
  def make_primary
    @idea.make_primary_version!
    redirect_to idea_path(@idea), notice: "v#{@idea.version_number} is now the primary version."
  end

  # GET /ideas/search?q=...
  # Quick search endpoint returning JSON results.
  def search
    query = params[:q].to_s.strip
    if query.blank?
      render json: { results: [] }
      return
    end

    search_term = "%#{query.downcase}%"
    ideas = @user.ideas.non_draft.where(discarded_at: nil)
                 .left_joins(:rich_text_description)
                 .where("LOWER(ideas.title) LIKE :q OR LOWER(action_text_rich_texts.body) LIKE :q", q: search_term)
                 .distinct
                 .order(updated_at: :desc)
                 .limit(20)
                 .map do |idea|
      {
        id: idea.id,
        title: idea.title,
        state: idea.state,
        score: idea.computed_score,
        url: idea_path(idea)
      }
    end

    render json: { results: ideas }
  end

  private

  def set_idea
    # Use with_discarded to find ideas even if they're archived
    @idea = @user.ideas.find_by(id: params[:id])
    unless @idea
      redirect_to ideas_path, alert: "Idea not found."
    end
  end

  def load_form_options
    @user.default_kanban_board if @user.kanban_boards.none?
    @kanban_boards = @user.kanban_boards.ordered.includes(:lists)
    @lists = @user.lists.kanban.includes(:kanban_board).order(:kanban_board_id, :position)
    @named_lists = @user.lists.named.ordered
    @topologies = @user.topologies.ordered
    @templates = @user.templates.order(:name)
  end

  def update_kanban_list_memberships
    if params.key?(:kanban_list_ids)
      update_board_scoped_kanban_memberships
    else
      update_legacy_kanban_membership
    end
  end

  def update_board_scoped_kanban_memberships
    selected_by_board = params.fetch(:kanban_list_ids, {}).to_unsafe_h

    selected_by_board.each do |board_id, list_id|
      board = @user.kanban_boards.find(board_id)
      current_memberships = @idea.idea_lists.joins(:list)
        .where(lists: { kind: "kanban", kanban_board_id: board.id })

      if list_id.blank?
        current_memberships.destroy_all
        next
      end

      list = board.lists.find(list_id)
      current_memberships.where.not(list_id: list.id).destroy_all
      @idea.idea_lists.find_or_create_by!(list: list)
    end
  end

  def update_legacy_kanban_membership
    @idea.idea_lists.joins(:list).where(lists: { kind: "kanban" }).destroy_all
    return if params[:list_id].blank?

    list = @user.lists.kanban.find(params[:list_id])
    @idea.idea_lists.create!(list: list)
  end

  def update_named_list_memberships
    selected_ids = Array(params[:named_list_ids]).reject(&:blank?).map(&:to_i)
    selected_lists = @user.lists.named.where(id: selected_ids)
    current_memberships = @idea.idea_lists.joins(:list).where(lists: { kind: "named" })

    current_memberships.where.not(list_id: selected_lists.select(:id)).destroy_all

    selected_lists.find_each do |list|
      @idea.idea_lists.find_or_create_by!(list: list)
    end
  end

  def add_idea_to_list(idea, list)
    return { membership: idea.idea_lists.find_or_create_by!(list: list), removed_list: nil } if list.named?

    add_idea_to_kanban_list(idea, list)
  end

  def add_idea_to_kanban_list(idea, new_list)
    ensure_idea_can_enter_kanban!(idea)

    removed_list = nil
    membership = nil

    ActiveRecord::Base.transaction do
      existing = idea.idea_lists.joins(:list)
        .where(lists: { kind: "kanban", kanban_board_id: new_list.kanban_board_id })
        .includes(:list)
        .first

      if existing&.list_id == new_list.id
        membership = existing
      elsif existing
        removed_list = existing.list
        removed_list.idea_lists.where("position > ?", existing.position).update_all("position = position - 1")
        membership = existing
        membership.update!(list: new_list, position: new_list.idea_lists.maximum(:position).to_i + 1)
      else
        membership = idea.idea_lists.create!(list: new_list)
      end
    end

    { membership: membership, removed_list: removed_list }
  end

  def ensure_idea_can_enter_kanban!(idea)
    return if idea.kanban_eligible?

    idea.errors.add(:base, idea.kanban_ineligibility_message)
    raise ActiveRecord::RecordInvalid, idea
  end

  def idea_list_membership_payload(idea, list, result)
    membership = result[:membership]
    board = list.kanban_board

    {
      success: true,
      message: "Added to #{list.name}.",
      idea: {
        id: idea.id
      },
      list: {
        id: list.id,
        name: list.name,
        kind: list.kind,
        kanban_board_id: list.kanban_board_id,
        board_name: board&.name
      },
      membership: {
        id: membership.id,
        position: membership.position
      },
      removed_list_id: result[:removed_list]&.id,
      board_list_ids: board ? board.lists.pluck(:id) : []
    }
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
    permitted = params.require(:idea).permit(
      :title, :tldr, :state, :template_id, :for_licensing,
      :trl, :difficulty, :opportunity, :timing,
      :difficulty_explanation, :opportunity_explanation, :timing_explanation,
      :description,
      :hero_image,
      :napkin_calculations,
      topology_ids: [],
      metadata: {}
    )
    permitted[:napkin_calculations] = parse_napkin_param(permitted[:napkin_calculations]) if permitted.key?(:napkin_calculations)
    permitted
  end

  def parse_napkin_param(raw)
    return nil if raw.blank?
    JSON.parse(raw)
  rescue JSON::ParserError
    nil
  end

  def kanban_assignment_requested?
    params.key?(:kanban_list_ids) || params.key?(:list_id)
  end

  def selected_kanban_list_requested?
    if params.key?(:kanban_list_ids)
      params.fetch(:kanban_list_ids, {}).to_unsafe_h.values.any?(&:present?)
    else
      params[:list_id].present?
    end
  end

  def apply_filters(ideas)
    # Filter by state
    if params[:state].present? && params[:state] != 'all'
      ideas = ideas.by_state(params[:state])
    end
    
    # Filter by TRL range
    if params[:trl_min].present? || params[:trl_max].present?
      trl_min = (params[:trl_min].presence || 0).to_i
      trl_max = (params[:trl_max].presence || 10).to_i
      ideas = ideas.where(trl: trl_min..trl_max)
    end

    # Filter by score range
    if params[:score_min].present? || params[:score_max].present?
      score_min = (params[:score_min].presence || -10).to_f
      score_max = (params[:score_max].presence || 10).to_f
      ideas = ideas.by_score_range(score_min, score_max)
    end
    
    # Filter by topology
    if params[:topology_id].present? && params[:topology_id] != 'all'
      ideas = ideas.joins(:idea_topologies).where(idea_topologies: { topology_id: params[:topology_id] })
    end
    
    # Filter by list
    if params[:list_id].present? && params[:list_id] != 'all'
      ideas = ideas.joins(:idea_lists).where(idea_lists: { list_id: params[:list_id] }).distinct
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

    # Full-text search across title and description
    if params[:search].present?
      search_term = "%#{params[:search].strip.downcase}%"
      ideas = ideas.left_joins(:rich_text_description)
                   .where(
                     "LOWER(ideas.title) LIKE :q OR LOWER(action_text_rich_texts.body) LIKE :q",
                     q: search_term
                   ).distinct
    end

    # Exclude archived ideas by default
    unless params[:include_archived] == 'true' || params[:state] == 'archived'
      ideas = ideas.where(discarded_at: nil)
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
