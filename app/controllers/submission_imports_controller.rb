class SubmissionImportsController < ApplicationController
  def new
    @source_options = NoteImportService.source_options
  end

  def preview
    @source_options = NoteImportService.source_options
    @preview = if params[:source] == "apple_notes" && Array(params[:files]).compact_blank.empty?
                 AppleNotesImportService.new.preview
               else
                 NoteImportService.new(
                   source: params[:source],
                   files: params[:files]
                 ).preview
               end
  rescue NoteImportService::ImportError => e
    redirect_to new_submission_import_path, alert: e.message
  end

  def create
    result = NoteImportService.import!(
      user: @user,
      payload: params[:import_payload],
      selected_folder_keys: params[:folder_keys],
      selected_note_keys: params[:note_keys]
    )

    redirect_to submissions_path(status: "pending", source: result.source),
                notice: "Imported #{result.imported_count} notes from #{result.folder_count} folders into intake."
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    redirect_to new_submission_import_path,
                alert: "That import batch has already been submitted."
  rescue NoteImportService::ImportError => e
    redirect_to new_submission_import_path, alert: e.message
  end

  def oauth
    service = NoteOauthImportService.new(
      source: params[:source],
      session: session,
      callback_url: oauth_callback_submission_import_url(source: params[:source])
    )

    redirect_to service.authorization_uri.to_s,
                allow_other_host: true
  rescue NoteImportService::ImportError => e
    redirect_to new_submission_import_path, alert: e.message
  end

  def oauth_callback
    @source_options = NoteImportService.source_options
    @preview = NoteOauthImportService.new(
      source: params[:source],
      session: session,
      callback_url: oauth_callback_submission_import_url(source: params[:source])
    ).preview_from_callback(params)
    render :preview
  rescue NoteImportService::ImportError => e
    redirect_to new_submission_import_path, alert: e.message
  end
end
