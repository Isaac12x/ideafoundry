class ListsController < ApplicationController
  before_action :set_user
  before_action :set_list, only: [:show, :edit, :update, :destroy, :send_email, :add_idea, :remove_idea]

  def index
    @default_view = normalized_list_view(params[:view].presence || @user.list_settings['default_view'])
    @kanban_lists = @user.lists.kanban.ordered.includes(ideas: [:idea_lists, :idea_entries])
    @named_lists = @user.lists.named.ordered.includes(:ideas)
    @lists = @kanban_lists
  end

  def show
    @ideas = @list.ideas.includes(:idea_lists, :idea_entries).order('idea_lists.position')
    @available_ideas = @user.ideas.non_draft.kept.order(:title).where.not(id: @list.idea_ids) if @list.named?
  end

  def new
    @list = @user.lists.build(kind: normalized_list_kind(params[:kind]))
  end

  def create
    @list = @user.lists.build(list_params)
    
    if @list.save
      redirect_to lists_path(view: @list.kind), notice: 'List was successfully created.'
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @list.update(list_params)
      redirect_to @list, notice: 'List was successfully updated.'
    else
      render :edit, status: :unprocessable_content
    end
  end

  def send_email
    recipients = params[:recipients].to_s.split(',').map(&:strip).reject(&:blank?)
    recipients = @user.email_recipients if recipients.empty?

    if recipients.empty?
      redirect_to lists_path, alert: 'No recipients configured. Add recipients in Settings > Email or enter an address.'
      return
    end

    recipients.each do |email|
      IdeaMailer.share_list(@list, email).deliver_later
    end

    redirect_to lists_path, notice: "List emailed to #{recipients.join(', ')}."
  end

  def destroy
    @list.destroy
    redirect_to lists_path, notice: 'List was successfully deleted.'
  end

  def add_idea
    unless @list.named?
      redirect_to @list, alert: 'Ideas can only be added directly to named lists.'
      return
    end

    idea = @user.ideas.non_draft.find(params[:idea_id])
    @list.idea_lists.find_or_create_by!(idea: idea)

    redirect_to @list, notice: 'Idea was added to the list.'
  end

  def remove_idea
    unless @list.named?
      redirect_to @list, alert: 'Ideas can only be removed directly from named lists.'
      return
    end

    @list.idea_lists.find_by!(idea_id: params[:idea_id]).destroy!

    redirect_to @list, notice: 'Idea was removed from the list.'
  end

  # PATCH /lists/update_idea_position
  def update_idea_position
    idea_id = params[:idea_id]
    new_list_id = params[:list_id]
    new_position = params[:position].to_i

    idea = @user.ideas.find(idea_id)
    new_list = @user.lists.kanban.find(new_list_id)

    old_list = nil

    ActiveRecord::Base.transaction do
      existing = idea.idea_lists.joins(:list).where(lists: { kind: "kanban" }).includes(:list).first

      if existing && existing.list == new_list
        # Reordering within same list
        old_position = existing.position
        new_list.idea_lists.where('position > ?', old_position).update_all('position = position - 1')
        new_list.idea_lists.where('position >= ?', new_position).update_all('position = position + 1')
        existing.update!(position: new_position)
      else
        # Moving to a different list
        if existing
          old_list = existing.list
          old_list.idea_lists.where('position > ?', existing.position).update_all('position = position - 1')
          existing.destroy!
        end

        new_list.idea_lists.where('position >= ?', new_position).update_all('position = position + 1')
        idea.idea_lists.create!(list: new_list, position: new_position)
      end
    end

    respond_to do |format|
      format.turbo_stream do
        streams = [
          turbo_stream.update("list_#{new_list.id}_ideas",
            partial: 'lists/ideas',
            locals: { list: new_list, ideas: new_list.ideas.includes(:idea_lists, :idea_entries).order('idea_lists.position') }
          )
        ]

        if old_list
          streams << turbo_stream.update("list_#{old_list.id}_ideas",
            partial: 'lists/ideas',
            locals: { list: old_list, ideas: old_list.ideas.reload.includes(:idea_lists, :idea_entries).order('idea_lists.position') }
          )
        end

        render turbo_stream: streams
      end
      format.json { head :ok }
    end
  rescue ActiveRecord::RecordNotFound => e
    respond_to do |format|
      format.turbo_stream { head :not_found }
      format.json { render json: { error: 'Record not found' }, status: :not_found }
    end
  rescue => e
    respond_to do |format|
      format.turbo_stream { head :unprocessable_content }
      format.json { render json: { error: e.message }, status: :unprocessable_content }
    end
  end

  private

  def set_list
    @list = @user.lists.find(params[:id])
  end

  def list_params
    permitted = [:name]
    permitted << :kind if action_name == "create"
    params.require(:list).permit(*permitted)
  end

  def normalized_list_kind(kind)
    List::KINDS.include?(kind.to_s) ? kind.to_s : "kanban"
  end

  def normalized_list_view(view)
    User::ALLOWED_LIST_DEFAULT_VIEWS.include?(view.to_s) ? view.to_s : User::DEFAULT_LIST_SETTINGS['default_view']
  end
end
