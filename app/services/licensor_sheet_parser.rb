require "roo"

# Reads an uploaded licensor spreadsheet (CSV/TSV/XLSX) into a plain grid of
# strings. Kept deliberately dumb: no mapping logic, no persistence — just
# "give me the rows", so the mapping UI and the importer share one reader.
class LicensorSheetParser
  class ParseError < StandardError; end

  # Caps keep a hostile or accidental 200k-row upload from eating the request.
  MAX_ROWS = 5_000
  MAX_COLUMNS = 60
  PREVIEW_ROWS = 25

  Grid = Struct.new(:rows, :truncated_rows, :truncated_columns, keyword_init: true) do
    def column_count
      @column_count ||= rows.map(&:size).max.to_i
    end

    def empty?
      rows.empty?
    end
  end

  # Opens the import's stored file and yields a parser for it. Active Storage
  # streams the blob to a tempfile, so Roo needs the extension told to it.
  def self.open(import)
    raise ParseError, "No file is attached to this import." unless import.file.attached?

    import.file.open do |tempfile|
      yield new(tempfile.path, extension: import.extension)
    end
  end

  def initialize(path, extension:)
    @path = path
    @extension = extension.to_s.downcase
  end

  def grid
    @grid ||= build_grid
  end

  private

  def build_grid
    sheet = spreadsheet
    return Grid.new(rows: [], truncated_rows: false, truncated_columns: false) if sheet.first_row.nil?

    last_row    = [sheet.last_row, sheet.first_row + MAX_ROWS - 1].min
    last_column = [sheet.last_column, sheet.first_column + MAX_COLUMNS - 1].min

    rows = (sheet.first_row..last_row).map do |row|
      (sheet.first_column..last_column).map { |col| format_cell(sheet.cell(row, col)) }
    end

    Grid.new(
      rows: drop_trailing_blank_rows(rows),
      truncated_rows: last_row < sheet.last_row,
      truncated_columns: last_column < sheet.last_column
    )
  rescue ParseError
    raise
  rescue StandardError => e
    raise ParseError, "That file could not be read (#{e.class.name.demodulize})."
  end

  def spreadsheet
    case @extension
    when ".csv"           then Roo::CSV.new(@path)
    when ".tsv"           then Roo::CSV.new(@path, csv_options: { col_sep: "\t" })
    when ".xlsx", ".xlsm" then Roo::Excelx.new(@path)
    else raise ParseError, "Unsupported file type '#{@extension}'."
    end
  end

  def drop_trailing_blank_rows(rows)
    rows.pop while rows.any? && rows.last.all?(&:blank?)
    rows
  end

  # Excel hands back Floats and Dates; render them the way the user typed them.
  def format_cell(value)
    case value
    when nil            then ""
    when Float          then value == value.to_i ? value.to_i.to_s : value.to_s
    when Date, DateTime then value.strftime("%Y-%m-%d")
    when Time           then value.strftime("%Y-%m-%d %H:%M")
    else value.to_s.strip
    end
  end
end
