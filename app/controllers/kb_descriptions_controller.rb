# "Fetch description" for a downloaded video/audio that has a source link but no saved description.
# Writes the Kb::Source sidecar, then reloads the file in the content frame (?desc= carries a failure hint).
class KbDescriptionsController < ApplicationController
  include KbFileLookup

  before_action :set_user

  def create
    file = locate_kb_file or return head(:not_found)
    return head(:forbidden) if private_kb_file?(file) # the link leaves this machine

    url = Kb::Source.read(file[:abs])["url"].presence || @user.kb_downloads.for_file(file[:src], file[:rel]).first&.url
    result = Kb::Source.fetch_description!(file[:abs], url)
    redirect_to kb_file_path(src: file[:src], file: file[:rel], desc: (result unless result == :ok)), status: :see_other
  end
end
