# "Pull the references too?" dialog for a web page saved into the KB: queues
# the cited sources the user picks, or dismisses the offer.
class KbReferencesController < ApplicationController
  before_action :set_user
  before_action :set_download

  def create
    urls = Array(params[:urls]).map(&:to_s)
    return respond_with(alert: "Pick at least one reference.") if urls.empty?

    queued = @download.pull_references!(urls)
    respond_with(notice: "Pulling #{queued} #{'reference'.pluralize(queued)} into #{@download.references_dir}/.")
  rescue ArgumentError => e
    respond_with(alert: e.message)
  end

  def destroy
    @download.update!(references_state: "dismissed") if @download.references_offered?
    respond_with
  end

  private

  def set_download
    @download = @user.kb_downloads.find(params[:id])
  end

  # Alerts keep the dialog open; anything else closes it.
  def respond_with(notice: nil, alert: nil)
    flash.now[:notice] = notice if notice
    flash.now[:alert] = alert if alert
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.update("flash", partial: "layouts/flash"),
          (turbo_stream.remove(helpers.dom_id(@download, :references)) unless alert),
          turbo_stream.replace("kb-sidebar-tree", partial: "kb/tree",
                               locals: { folders: Kb::TreeBuilder.build(@user), selected_file: nil, selected_folder_index: nil })
        ].compact
      end
      format.html { redirect_to kb_path, notice: notice, alert: alert }
    end
  end
end
