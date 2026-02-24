class BuildItemsController < ApplicationController
  before_action :set_user
  before_action :set_build_item, only: [:edit, :update, :destroy, :toggle]

  def index
    @build_items = @user.build_items.pending
    @completed_items = @user.build_items.done
    @build_item = @user.build_items.build
  end

  def create
    @build_item = @user.build_items.build(build_item_params)

    if @build_item.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to build_items_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("build_item_form", partial: "build_items/form", locals: { build_item: @build_item }), status: :unprocessable_entity }
        format.html { redirect_to build_items_path, alert: @build_item.errors.full_messages.join(", ") }
      end
    end
  end

  def edit
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.replace("build_item_#{@build_item.id}", partial: "build_items/edit_form", locals: { build_item: @build_item }) }
      format.html
    end
  end

  def update
    if @build_item.update(build_item_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to build_items_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("build_item_#{@build_item.id}", partial: "build_items/edit_form", locals: { build_item: @build_item }), status: :unprocessable_entity }
        format.html { render :edit, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @build_item.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to build_items_path, notice: "Item removed." }
    end
  end

  def toggle
    if @build_item.completed?
      @build_item.mark_pending!
    else
      @build_item.mark_completed!
    end

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to build_items_path }
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

  def build_item_params
    permitted = params.require(:build_item).permit(:title, :description, :links_json)
    if permitted[:links_json].present?
      permitted[:links] = JSON.parse(permitted[:links_json]) rescue []
    end
    permitted.except(:links_json)
  end
end
