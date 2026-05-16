class FactsController < ApplicationController
  before_action :set_user

  def create
    @fact = @user.facts.build(fact_params)
    if @fact.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to kb_path(tab: "facts") }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("fact_form", partial: "facts/form", locals: { error: @fact.errors.full_messages.first }) }
        format.html { redirect_to kb_path(tab: "facts") }
      end
    end
  end

  def destroy
    @fact = @user.facts.find(params[:id])
    @fact.destroy
    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to kb_path(tab: "facts") }
    end
  end

  private

  def fact_params
    params.require(:fact).permit(:body)
  end
end
