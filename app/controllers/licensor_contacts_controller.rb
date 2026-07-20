class LicensorContactsController < ApplicationController
  before_action :set_user
  before_action :set_licensor

  def create
    @contact = @licensor.contacts.build(contact_params)
    if @contact.save
      respond_to do |format|
        format.turbo_stream { render turbo_stream: contact_streams }
        format.html { redirect_back fallback_location: licensing_crm_path, notice: "Contact logged." }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: contact_streams, status: :unprocessable_content }
        format.html { redirect_back fallback_location: licensing_crm_path, alert: @contact.errors.full_messages.join(", ") }
      end
    end
  end

  def destroy
    @contact = @licensor.contacts.find(params[:id])
    @contact.destroy
    respond_to do |format|
      format.turbo_stream { render turbo_stream: contact_streams }
      format.html { redirect_back fallback_location: licensing_crm_path, notice: "Contact removed." }
    end
  end

  private

  def set_licensor
    @licensor = Licensor.where(idea_id: @user.ideas.select(:id)).find(params[:licensor_id])
  end

  def contact_params
    params.require(:licensor_contact).permit(:occurred_at, :channel, :summary)
  end

  # The log form lives in two places: the idea's Potential Licensors tab and the
  # CRM record panel. Re-render whichever the request came from.
  def contact_streams
    @licensor.reload
    if params[:context] == "tab"
      idea = @licensor.idea
      [turbo_stream.replace("licensors_tab_#{idea.id}", partial: "licensors/tab", locals: { idea: idea, licensor: Licensor.new })]
    else
      ideas = @user.ideas.for_licensing.where(discarded_at: nil)
      licensors = Licensor.where(idea_id: ideas.select(:id)).includes(:idea).ordered
      [
        turbo_stream.replace("licensor-panel", partial: "licensing/crm/record_panel", locals: { licensor: @licensor }),
        turbo_stream.replace("crm-board", partial: "licensing/crm/board", locals: { by_stage: licensors.group_by(&:stage) })
      ]
    end
  end
end
