class MoodImagesController < ApplicationController
  before_action :set_image, only: %i[update destroy]

  # Upload one or more images onto a board. idea_id present -> that idea's board;
  # absent -> the global "Think in Images" board shown in the KB tab.
  def create
    idea = @user.ideas.find(params[:idea_id]) if params[:idea_id].present?
    base = @user.mood_images.where(idea_id: idea&.id).count

    @images = Array(params[:files]).reject(&:blank?).each_with_index.map do |file, i|
      img = @user.mood_images.new(idea: idea)
      # Cascade fresh tiles into a loose grid so they don't stack exactly.
      slot = base + i
      img.pos_x = 40 + (slot % 6) * 210
      img.pos_y = 40 + (slot / 6) * 170
      img.z_index = slot
      img.file.attach(file)
      img.save!
      img
    end

    respond_to do |format|
      format.turbo_stream
      format.json { render json: { count: @images.size } }
    end
  end

  def update
    @image.update(image_params)
    head :ok
  end

  def destroy
    @image.destroy
    head :ok
  end

  private

  def set_image
    @image = @user.mood_images.find(params[:id])
  end

  def image_params
    params.require(:mood_image).permit(:pos_x, :pos_y, :z_index, :caption)
  end
end
