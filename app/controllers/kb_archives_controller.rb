# Peeks inside a KB archive without extracting it (see Kb::Archive): the frame content for archives,
# comics (.cbz/.cbr/...) and Fusion .f3d previews, plus one entry streamed on demand.
class KbArchivesController < ApplicationController
  include KbFileLookup

  before_action :set_user
  before_action :set_file

  PREVIEW_HINT = /thumb|preview|screenshot/i

  def show
    @kind = Kb::MediaTypes.kind_for(@file[:abs])
    @listing = Kb::Archive.list(@file[:abs])
    @pages = Kb::Archive.pages(@listing) if @kind == :comic
    @preview = preview_entry(@listing) if @kind == :cad
  rescue Kb::Archive::Error => e
    @error = e.message
  end

  # Raster images stream inline (comic pages, thumbnails); everything else is a forced download.
  def entry
    name = params[:entry].to_s
    return unless stale?(etag: [ File.mtime(@file[:abs]).to_f, File.size(@file[:abs]), name ], cache_control: { private: true, max_age: 300 })

    data = Kb::Archive.read_entry(@file[:abs], name)
    ext = File.extname(name).downcase
    inline = Kb::Archive::PAGE_EXTENSIONS.include?(ext)
    response.set_header("X-Content-Type-Options", "nosniff")
    response.set_header("Content-Security-Policy", "sandbox; default-src 'none'")
    send_data data, filename: File.basename(name), type: inline ? Kb::MediaTypes.mime_type_for(name) : "application/octet-stream",
                    disposition: inline ? "inline" : "attachment"
  rescue Kb::Archive::NotFound then head(:not_found)
  rescue Kb::Archive::TooLarge then head(:content_too_large)
  rescue Kb::Archive::Error => e then render plain: e.message, status: :unprocessable_content
  end

  private

  def set_file
    @file = locate_kb_file
    head(:not_found) unless @file && Kb::MediaTypes.kind_for(@file[:abs]).in?(%i[archive comic cad]) && Kb::Archive.format_for(@file[:abs])
  end

  # Fusion keeps a PNG thumbnail in the archive; prefer one that says so, else the biggest.
  def preview_entry(listing)
    pngs = listing.files.select { |entry| File.extname(entry.path).casecmp?(".png") && entry.size.to_i.between?(1, 5.megabytes) }
    pngs.find { |entry| entry.path.match?(PREVIEW_HINT) } || pngs.max_by(&:size)
  end
end
