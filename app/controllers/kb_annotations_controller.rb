# JSON endpoints behind the KB viewer's highlight/underline toolbar.
class KbAnnotationsController < ApplicationController
  before_action :set_user
  before_action :set_file, only: [ :index, :create ]
  before_action :block_locking, only: :create

  def index
    render json: @user.kb_annotations.for_file(@source_path, @relative_path).in_reading_order
  end

  def create
    mark = @user.kb_annotations.create!(
      annotation_params.merge(source_path: @source_path, relative_path: @relative_path)
    )
    render json: mark, status: :created
  rescue ActiveRecord::RecordInvalid => error
    render json: { error: error.record.errors.full_messages.to_sentence }, status: :unprocessable_content
  end

  def update
    mark = @user.kb_annotations.find(params[:id])
    return if locking?(mark.source_path, mark.relative_path)

    if mark.update(annotation_params.slice(:style, :color))
      render json: mark
    else
      render json: { error: mark.errors.full_messages.to_sentence }, status: :unprocessable_content
    end
  end

  def destroy
    mark = @user.kb_annotations.find(params[:id])
    return if locking?(mark.source_path, mark.relative_path)

    mark.destroy!
    head :no_content
  end

  private

  # A project that is locking would lose (or leak) a mark made now.
  def block_locking
    locking?(@source_path, @relative_path)
  end

  def locking?(base, rel)
    return false unless Kb::ProjectLock.busy_path?(File.join(base, rel))

    render json: { error: "This project is locking or unlocking. Try again in a moment." }, status: :conflict
    true
  end

  def set_file
    source = KbSource.list(@user)[params[:src].to_i]
    return head(:not_found) unless source && params[:src].to_i >= 0

    @source_path = File.expand_path(source[:path])
    @relative_path = IdeaKbLink.normalize_relative_path(params[:file])
    absolute = File.expand_path(File.join(@source_path, @relative_path))
    head(:not_found) unless @relative_path.present? && absolute.start_with?("#{@source_path}/") && File.file?(absolute)
  end

  def annotation_params
    params.require(:annotation).permit(:style, :color, :page, :start_offset, :end_offset, :quote, :prefix, :suffix)
  end
end
