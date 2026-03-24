class ListsController < ApplicationController
  before_action :set_user
  before_action :set_list, only: [:show, :edit, :update, :destroy, :send_email]

  def index
    @lists = @user.lists.ordered.includes(ideas: :idea_lists)
  end

  def show
    @ideas = @list.ideas.includes(:idea_lists).order('idea_lists.position')
  end

  def new
    @list = @user.lists.build
  end

  def create
    @list = @user.lists.build(list_params)
    
    if @list.save
      redirect_to lists_path, notice: 'List was successfully created.'
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

  # PATCH /lists/update_idea_position
  def update_idea_position
    idea_id = params[:idea_id]
    new_list_id = params[:list_id]
    new_position = params[:position].to_i

    idea = @user.ideas.find(idea_id)
    new_list = @user.lists.find(new_list_id)

    old_list = nil

    ActiveRecord::Base.transaction do
      existing = idea.idea_lists.includes(:list).first

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
            locals: { list: new_list, ideas: new_list.ideas.includes(:idea_lists).order('idea_lists.position') }
          )
        ]

        if old_list
          streams << turbo_stream.update("list_#{old_list.id}_ideas",
            partial: 'lists/ideas',
            locals: { list: old_list, ideas: old_list.ideas.reload.includes(:idea_lists).order('idea_lists.position') }
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
    params.require(:list).permit(:name)
  end
end