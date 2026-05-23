class MaximsController < ApplicationController
  before_action :set_user

  def create
    @maxim = @user.maxims.build(maxim_params)
    if @maxim.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to kb_path(tab: "maxims") }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("maxim_form", partial: "maxims/form", locals: { error: @maxim.errors.full_messages.first }) }
        format.html { redirect_to kb_path(tab: "maxims") }
      end
    end
  end

  def destroy
    @maxim = @user.maxims.find(params[:id])
    @maxim.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to kb_path(tab: "maxims") }
    end
  end

  private

  def maxim_params
    params.require(:maxim).permit(:body)
  end
end
