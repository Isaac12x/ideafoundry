# Readable form of a KB ebook: GET reports the sidecar conversion state (EPUB, or PDF for DjVu);
# POST starts the local Calibre/ddjvu conversion. Runs entirely on this machine, so private projects are allowed.
class KbBooksController < ApplicationController
  include KbFileLookup

  before_action :set_user
  before_action :set_file

  def show
    render json: payload
  end

  def create
    abs = @file[:abs]
    return render json: payload if Kb::BookConversion.ready?(abs)
    return render json: payload.merge(error: Kb::BookConversion.install_hint(abs)), status: :unprocessable_content unless Kb::BookConversion.tool(abs)
    return render json: { error: "This project is locking or unlocking. Try again in a moment." }, status: :conflict if Kb::ProjectLock.busy_path?(abs)

    KbBookConvertJob.perform_later(abs) if Kb::BookConversion.claim!(abs)
    render json: payload, status: :accepted
  end

  private

  def set_file
    @file = locate_kb_file
    head(:not_found) unless @file && Kb::MediaTypes.kind_for(@file[:abs]) == :book
  end

  # status: ready | running | failed | missing_tool | none ("ready" carries the sidecar's serve url)
  def payload
    abs = @file[:abs]
    ready = Kb::BookConversion.ready?(abs)
    running = !ready && Kb::BookConversion.running?(abs)
    tool = Kb::BookConversion.tool(abs)
    err = Kb::BookConversion.error(abs)
    status = if ready then "ready" elsif running then "running" elsif err then "failed" elsif tool.nil? then "missing_tool" else "none" end
    side = Kb::BookConversion.sidecar(abs)
    { status: status, format: Kb::BookConversion.format(abs), error: err,
      hint: (Kb::BookConversion.install_hint(abs) if status == "missing_tool"),
      url: (kb_serve_path(src: @file[:src], file: File.join(File.dirname(@file[:rel]), File.basename(side)).delete_prefix("./"), v: (File.mtime(side).to_f * 1000).to_i) if ready) }
  end
end
