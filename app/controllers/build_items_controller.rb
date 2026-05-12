class BuildItemsController < ApplicationController
  before_action :require_backlog_enabled
  before_action :set_user
  before_action :set_build_item, only: [:edit, :cancel_edit, :update, :destroy, :toggle, :toggle_checklist_item]

  def index
    @build_items = @user.build_items.pending
    @completed_items = @user.build_items.done
    @build_item = @user.build_items.build
  end

  def create
    @build_item = @user.build_items.build(build_item_params)

    if @build_item.save
      @pending_index = pending_index(@build_item)
      assign_counts
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to build_items_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("build_item_form", partial: "build_items/form", locals: { build_item: @build_item }), status: :unprocessable_content }
        format.html { redirect_to build_items_path, alert: @build_item.errors.full_messages.join(", ") }
      end
    end
  end

  def edit
    @pending_index = pending_index(@build_item)
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("build_item_#{@build_item.id}", partial: "build_items/edit_form", locals: { build_item: @build_item }) }
      format.html
    end
  end

  def cancel_edit
    @pending_index = pending_index(@build_item)
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to build_items_path }
    end
  end

  def update
    if @build_item.update(build_item_params)
      @pending_index = pending_index(@build_item)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to build_items_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("build_item_#{@build_item.id}", partial: "build_items/edit_form", locals: { build_item: @build_item }), status: :unprocessable_content }
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  def destroy
    @destroyed_completed = @build_item.completed?
    @build_item_id = @build_item.id
    @build_item.destroy
    assign_counts
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to build_items_path, notice: "Item removed." }
    end
  end

  def toggle
    if @build_item.completed?
      @build_item.mark_pending!
    elsif @build_item.checklist_blocking_completion?
      @toggle_blocked = true
      @build_item.errors.add(:base, "Complete subitems first.")
    else
      @build_item.mark_completed!
    end

    assign_counts
    @pending_index = pending_index(@build_item)
    respond_to do |format|
      format.turbo_stream { render :toggle, status: (@toggle_blocked ? :unprocessable_content : :ok) }
      format.html do
        if @toggle_blocked
          redirect_to build_items_path, alert: "Complete subitems first."
        else
          redirect_to build_items_path
        end
      end
    end
  end

  def toggle_checklist_item
    if @build_item.toggle_checklist_item!(params[:line])
      @pending_index = pending_index(@build_item)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to build_items_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { head :unprocessable_content }
        format.html { redirect_to build_items_path, alert: "Checklist item could not be updated." }
      end
    end
  end

  def reorder
    order = params[:order] || []
    ActiveRecord::Base.transaction do
      order.each_with_index do |id, index|
        @user.build_items.where(id: id).update_all(position: index + 1)
      end
    end

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.json { head :ok }
    end
  end

  private

  def set_build_item
    @build_item = @user.build_items.find(params[:id])
  end

  def assign_counts
    @pending_count = @user.build_items.pending.size
    @done_count = @user.build_items.done.size
    @total_count = @pending_count + @done_count
  end

  def pending_index(build_item)
    @user.build_items.pending.pluck(:id).index(build_item.id) || 0
  end

  def build_item_params
    permitted = params.require(:build_item).permit(:title, :description, :links_json)
    if permitted[:links_json].present?
      permitted[:links] = JSON.parse(permitted[:links_json]) rescue []
    end
    permitted.except(:links_json)
  end
end
