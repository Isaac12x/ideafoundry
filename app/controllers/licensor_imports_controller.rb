# Upload → map columns → create licensors. The uploaded sheet is kept with the
# mapping, so an import can be reopened and re-run without a fresh upload.
class LicensorImportsController < ApplicationController
  before_action :set_user
  before_action -> { require_feature(:licensing) }
  before_action :set_idea, only: [ :new, :create ]
  before_action :set_import, only: [ :show, :update, :destroy ]

  def new
    @import = @idea.licensor_imports.new
    @previous_imports = @idea.licensor_imports.recent.limit(5)
  end

  def create
    upload = params[:file]
    @import = @idea.licensor_imports.new(filename: upload.try(:original_filename).to_s)
    @import.file.attach(upload) if upload.present?

    if @import.save
      redirect_to licensor_import_path(@import)
    else
      @previous_imports = @idea.licensor_imports.recent.limit(5)
      flash.now[:alert] = @import.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end
  end

  # The mapping screen: the sheet as the user sees it, plus a field picker per column.
  def show
    load_grid or return
    @mapping = @import.mapping.presence || suggested_mapping
  end

  def update
    @import.headers_in_first_row = params[:headers_in_first_row] == "1"
    @import.column_mapping = submitted_mapping
    load_grid or return

    if (error = mapping_error)
      @mapping = @import.column_mapping
      flash.now[:alert] = error
      return render :show, status: :unprocessable_content
    end

    @import.save!
    result = LicensorImporter.call(@import, @grid)
    # Imported licensors are only visible in the CRM if the idea is flagged.
    @idea = @import.idea
    @idea.update!(for_licensing: true) unless @idea.for_licensing?

    redirect_to licensing_crm_path, notice: result.summary
  end

  def destroy
    idea = @import.idea
    @import.destroy
    redirect_to new_idea_licensor_import_path(idea), notice: "Import discarded."
  end

  private

  def set_idea
    @idea = @user.ideas.find(params[:idea_id])
  end

  def set_import
    @import = LicensorImport.where(idea_id: @user.ideas.select(:id)).find(params[:id])
  end

  # Reads the stored sheet into @grid, or bails out to the upload screen.
  def load_grid
    LicensorSheetParser.open(@import) { |parser| @grid = parser.grid }

    if @grid.empty?
      redirect_to new_idea_licensor_import_path(@import.idea), alert: "That file has no rows to import."
      return false
    end

    true
  rescue LicensorSheetParser::ParseError => e
    redirect_to new_idea_licensor_import_path(@import.idea), alert: e.message
    false
  end

  # { column_index => field }, keeping only real fields the user picked.
  def submitted_mapping
    (params[:mapping] || {}).to_unsafe_h.each_with_object({}) do |(index, field), acc|
      next unless LicensorImport::FIELDS.include?(field.to_s)

      acc[index.to_s] = field.to_s
    end
  end

  def mapping_error
    fields = @import.column_mapping.values
    duplicated = fields.tally.select { |_field, count| count > 1 }.keys

    if fields.exclude?("company")
      "Map one column to Company — it is the only field a licensor must have."
    elsif duplicated.any?
      "#{duplicated.map { |f| LicensorImport.field_label(f) }.to_sentence} mapped to more than one column."
    end
  end

  # First pass at the mapping, from the header row's wording.
  def suggested_mapping
    return {} unless @import.headers_in_first_row?

    taken = []
    @grid.rows.first.each_with_index.each_with_object({}) do |(header, index), acc|
      field = LicensorImport.guess_field(header)
      next if field.nil? || taken.include?(field)

      taken << field
      acc[index.to_s] = field
    end
  end
end
