class SubmissionImportsController < ApplicationController
  def new
    @source_options = NoteImportService.source_options
  end

  def preview
    @source_options = NoteImportService.source_options
    @preview = NoteImportService.new(
      source: params[:source],
      files: params[:files]
    ).preview
  rescue NoteImportService::ImportError => e
    redirect_to new_submission_import_path, alert: e.message
  end

  def create
    result = NoteImportService.import!(
      user: @user,
      payload: params[:import_payload],
      selected_folder_keys: params[:folder_keys]
    )

    redirect_to submissions_path(status: "pending", source: result.source),
                notice: "Imported #{result.imported_count} notes from #{result.folder_count} folders into intake."
  rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
    redirect_to new_submission_import_path,
                alert: "That import batch has already been submitted."
  rescue NoteImportService::ImportError => e
    redirect_to new_submission_import_path, alert: e.message
  end
end
