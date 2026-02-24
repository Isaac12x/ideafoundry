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
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @list.update(list_params)
      redirect_to @list, notice: 'List was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
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

    # Find or create the idea_list association
    idea_list = idea.idea_lists.find_by(list: new_list)
    
    if idea_list.nil?
      # Moving to a new list
      idea_list = idea.idea_lists.build(list: new_list)
    end

    # Update positions in a transaction
    ActiveRecord::Base.transaction do
      # Remove from current position if it exists
      if idea_list.persisted?
        old_position = idea_list.position
        old_list = idea_list.list
        
        # Shift other items up in the old list
        old_list.idea_lists.where('position > ?', old_position).update_all('position = position - 1')
      end

      # Make room in the new position
      new_list.idea_lists.where('position >= ?', new_position).update_all('position = position + 1')
      
      # Set the new position
      idea_list.position = new_position
      idea_list.save!
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace("list_#{new_list.id}_ideas", 
            partial: 'lists/ideas', 
            locals: { list: new_list, ideas: new_list.ideas.includes(:idea_lists).order('idea_lists.position') }
          ),
          # If the idea moved between lists, update the old list too
          if idea_list.list_id_was && idea_list.list_id_was != new_list.id
            old_list = List.find(idea_list.list_id_was)
            turbo_stream.replace("list_#{old_list.id}_ideas",
              partial: 'lists/ideas',
              locals: { list: old_list, ideas: old_list.ideas.includes(:idea_lists).order('idea_lists.position') }
            )
          end
        ].compact
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
      format.turbo_stream { head :unprocessable_entity }
      format.json { render json: { error: e.message }, status: :unprocessable_entity }
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