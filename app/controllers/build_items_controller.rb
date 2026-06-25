class BuildItemsController < ApplicationController
  before_action :require_backlog_enabled
  before_action :set_user
  before_action :set_build_item, only: [:edit, :cancel_edit, :update, :destroy, :toggle, :toggle_checklist_item, :pin]
  after_action :export_backlog_file, only: [:create, :update, :destroy, :toggle, :toggle_checklist_item, :reorder, :pin, :join], if: -> { @backlog_changed }

  def index
    BacklogFileSync.sync_from_file(@user)
    @build_items = @user.build_items.pending.with_attached_images.to_a
    @completed_items = @user.build_items.done.with_attached_images.to_a
    assign_counts(@build_items, @completed_items)
    @build_item = @user.build_items.build
  end

  def create
    @build_item = @user.build_items.build(build_item_params)

    if @build_item.save
      @backlog_changed = true
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
    attributes = build_item_params
    images = attributes.delete(:images)

    @build_item.assign_attributes(attributes)
    @build_item.images.attach(images) if images.present?

    if @build_item.save
      @backlog_changed = true
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
    @backlog_changed = true
    assign_counts
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to build_items_path, notice: "Item removed." }
    end
  end

  def toggle
    if @build_item.completed?
      @build_item.mark_pending!
      @backlog_changed = true
    elsif @build_item.checklist_blocking_completion?
      @toggle_blocked = true
      @build_item.errors.add(:base, "Complete subitems first.")
    else
      @build_item.mark_completed!
      @backlog_changed = true
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
      @backlog_changed = true
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
    @backlog_changed = order.any?

    respond_to do |format|
      format.turbo_stream { head :ok }
      format.json { head :ok }
    end
  end

  def pin
    @build_item.update(pinned: !@build_item.pinned?)
    @backlog_changed = true
    @build_items = @user.build_items.pending.with_attached_images.to_a
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to build_items_path }
    end
  end

  def join
    source = @user.build_items.find(params[:source_id])
    @target = @user.build_items.find(params[:target_id])

    if source.id == @target.id || source.completed? || @target.completed?
      return respond_to do |format|
        format.turbo_stream { head :unprocessable_content }
        format.html { redirect_to build_items_path, alert: "Items could not be joined." }
      end
    end

    @source_id = source.id
    @target.absorb!(source)
    @backlog_changed = true
    @pending_index = pending_index(@target)
    assign_counts
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to build_items_path }
    end
  end

  private

  def export_backlog_file
    BacklogFileSync.export(@user)
  end

  def set_build_item
    @build_item = @user.build_items.find(params[:id])
  end

  # Sets top-level item counts (used for Turbo-stream branching) plus the
  # display counts that fold in checklist subitems (used by the stats header).
  def assign_counts(pending = nil, completed = nil)
    pending ||= @user.build_items.pending.to_a
    completed ||= @user.build_items.done.to_a
    @pending_count = pending.size
    @done_count = completed.size

    subitems = BuildItem.subitem_totals(pending + completed)
    @done_display = @done_count + subitems[:done]
    @queued_display = @pending_count + (subitems[:total] - subitems[:done])
    @total_display = @done_display + @queued_display
  end

  def pending_index(build_item)
    @user.build_items.pending.pluck(:id).index(build_item.id) || 0
  end

  def build_item_params
    permitted = params.require(:build_item).permit(:title, :description, :links_json, :pinned, images: [])
    if permitted[:links_json].present?
      permitted[:links] = JSON.parse(permitted[:links_json]) rescue []
    end
    permitted.except(:links_json)
  end
end
