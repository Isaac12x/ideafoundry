class LicensorsController < ApplicationController
  before_action :set_user
  before_action :set_idea, only: [:create]
  before_action :set_licensor, only: [:show, :update, :destroy]

  def create
    @licensor = @idea.licensors.build(licensor_params)
    if @licensor.save
      respond_to do |format|
        format.turbo_stream { render turbo_stream: licensors_tab_stream(@idea) }
        format.html { redirect_to idea_path(@idea, anchor: "licensors") }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: licensors_tab_stream(@idea, @licensor), status: :unprocessable_content }
        format.html { redirect_to idea_path(@idea), alert: @licensor.errors.full_messages.join(", ") }
      end
    end
  end

  # Renders the CRM slide-over record panel into its Turbo frame.
  def show
    render partial: "licensing/crm/record_panel", locals: { licensor: @licensor }
  end

  def update
    if @licensor.update(licensor_params)
      respond_to do |format|
        format.turbo_stream { render turbo_stream: update_streams }
        format.json { render json: { ok: true, stage: @licensor.stage } }
        format.html { redirect_back fallback_location: licensing_crm_path }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: update_streams(errors: true), status: :unprocessable_content }
        format.json { render json: { ok: false, errors: @licensor.errors.full_messages }, status: :unprocessable_content }
        format.html { redirect_back fallback_location: licensing_crm_path, alert: @licensor.errors.full_messages.join(", ") }
      end
    end
  end

  def destroy
    idea = @licensor.idea
    @licensor.destroy
    respond_to do |format|
      format.turbo_stream do
        streams = case params[:context]
                  when "board", "panel" then [board_stream, turbo_stream.remove("licensor-panel")]
                  else licensors_tab_stream(idea)
                  end
        render turbo_stream: streams
      end
      format.html { redirect_back fallback_location: licensing_crm_path, notice: "Licensor removed." }
    end
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end

  def set_licensor
    @licensor = Licensor.where(idea_id: @user.ideas.select(:id)).find(params[:id])
  end

  def licensor_params
    params.require(:licensor).permit(
      :company, :contact_name, :contact_email, :contact_url,
      :notes, :next_action, :stage, :position
    )
  end

  # Streams for #update, branched by where the edit came from.
  def update_streams(errors: false)
    case params[:context]
    when "board"
      [board_stream]
    when "panel"
      [board_stream, turbo_stream.replace("licensor-panel", partial: "licensing/crm/record_panel", locals: { licensor: @licensor })]
    else
      licensors_tab_stream(@licensor.idea)
    end
  end

  def board_stream
    turbo_stream.replace("crm-board", partial: "licensing/crm/board", locals: crm_board_locals)
  end

  def licensors_tab_stream(idea, form_licensor = nil)
    turbo_stream.replace(
      "licensors_tab_#{idea.id}",
      partial: "licensors/tab",
      locals: { idea: idea, licensor: form_licensor || Licensor.new }
    )
  end

  def crm_board_locals
    ideas = @user.ideas.for_licensing.where(discarded_at: nil)
    licensors = Licensor.where(idea_id: ideas.select(:id)).includes(:idea).ordered
    { by_stage: licensors.group_by(&:stage) }
  end
end
