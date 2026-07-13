module Licensing
  class CrmController < ApplicationController
    before_action :set_user

    def index
      @ideas = @user.ideas.for_licensing.where(discarded_at: nil).order(:title)
      @licensors = Licensor.where(idea_id: @ideas.select(:id)).includes(:idea, :contacts).ordered
      @by_stage = @licensors.group_by(&:stage)
      @view = params[:view] == "table" ? "table" : "board"
    end
  end
end
