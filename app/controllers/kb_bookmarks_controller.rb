# JSON endpoints behind the KB viewer's Bookmarks panel (pdf, comic, book).
class KbBookmarksController < ApplicationController
  include KbFileLookup

  before_action :set_user
  before_action :set_file, only: [ :index, :create ]
  before_action :block_locking, only: :create

  def index
    render json: @user.kb_bookmarks.for_file(@source_path, @relative_path).in_reading_order
  end

  def create
    mark = @user.kb_bookmarks.build(bookmark_params.merge(source_path: @source_path, relative_path: @relative_path))
    save_and_render(mark, :created)
  end

  def update
    mark = @user.kb_bookmarks.find(params[:id])
    return if locking?(mark.source_path, mark.relative_path)

    mark.label = bookmark_params[:label]
    save_and_render(mark, :ok)
  end

  def destroy
    mark = @user.kb_bookmarks.find(params[:id])
    return if locking?(mark.source_path, mark.relative_path)

    mark.destroy!
    head :no_content
  end

  private

  def save_and_render(mark, status)
    if mark.save
      render json: mark, status: status
    else
      render json: { error: mark.errors.full_messages.to_sentence }, status: :unprocessable_content
    end
  end

  # A locking project would lose (or leak) a bookmark made now.
  def block_locking
    locking?(@source_path, @relative_path)
  end

  def locking?(base, rel)
    return false unless Kb::ProjectLock.busy_path?(File.join(base, rel))

    render json: { error: "This project is locking or unlocking. Try again in a moment." }, status: :conflict
    true
  end

  def set_file
    located = locate_kb_file
    return head(:not_found) unless located

    @source_path = located[:root]
    @relative_path = located[:rel]
  end

  def bookmark_params
    params.require(:bookmark).permit(:label, :page, :cfi, :progress)
  end
end
