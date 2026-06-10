require "digest"
require "sqlite3"
require "zlib"

class AppleNotesImportService
  DEFAULT_PATHS = [
    "~/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite",
    "~/Library/Containers/com.apple.Notes/Data/Library/Notes/NotesV7.storedata",
    "~/Library/Containers/com.apple.Notes/Data/Library/Notes/NotesV6.storedata"
  ].freeze

Add error handling to raise a clear exception if no database path is found.
    @database_path = database_path.presence || self.class.discover_database_path
  end

  def self.discover_database_path
    DEFAULT_PATHS.map { |path| File.expand_path(path) }
                 .find { |path| File.file?(path) && File.readable?(path) }
  end

  def preview
    raise NoteImportService::ImportError, "Apple Notes database was not found on this Mac." if database_path.blank?

    notes = extract_notes.first(NoteImportService::MAX_NOTES)
    raise NoteImportService::ImportError, "No readable Apple Notes were found in #{database_path}." if notes.empty?

    NoteImportService.preview_from_notes(source: "apple_notes", notes: notes)
  rescue SQLite3::Exception => e
    raise NoteImportService::ImportError, "Apple Notes database could not be opened: #{e.message}"
  end

  private

  attr_reader :database_path

  def extract_notes
    db = SQLite3::Database.new(database_path, readonly: true)
    db.results_as_hash = true

    note_rows(db).filter_map do |row|
      title = first_present(row, note_title_columns(db))
      body = note_body(row, db)
      folder = folder_name(row, db)
      identifier = first_present(row, %w[ZIDENTIFIER ZGUID ZUUID Z_PK]) || Digest::SHA256.hexdigest(row.inspect)

      NoteImportService.build_import_note(
        title: title,
        body: body,
        folders: [folder],
        source_path: "Apple Notes/#{folder}/#{identifier}",
        metadata: {
          "apple_notes_identifier" => identifier,
          "database_path" => database_path
        }
      )
    end
  ensure
    db&.close
  end

  def note_rows(db)
    table = table_name(db)
    columns = columns_for(db, table)
    predicates = []
    predicates << "ZMARKEDFORDELETION IS NULL OR ZMARKEDFORDELETION = 0" if columns.include?("ZMARKEDFORDELETION")
    predicates << "ZTRASHED IS NULL OR ZTRASHED = 0" if columns.include?("ZTRASHED")

    note_marker = if columns.include?("ZFOLDER")
                    "ZFOLDER IS NOT NULL"
                  elsif columns.include?("ZBODY") || columns.include?("ZSNIPPET")
                    "(#{%w[ZBODY ZSNIPPET ZTEXT ZHTMLSTRING].select { |column| columns.include?(column) }.map { |column| "#{column} IS NOT NULL" }.join(" OR ")})"
                  end

    predicates << note_marker if note_marker.present?
    where = predicates.compact_blank.map { |predicate| "(#{predicate})" }.join(" AND ")
    sql = "SELECT * FROM #{quote_identifier(table)}"
    sql += " WHERE #{where}" if where.present?
    sql += " ORDER BY #{order_column(columns)} DESC" if order_column(columns)

    db.execute(sql)
  end

  def table_name(db)
    names = table_names(db)
    return "ZICCLOUDSYNCINGOBJECT" if names.include?("ZICCLOUDSYNCINGOBJECT")
    return "ZNOTE" if names.include?("ZNOTE")

    raise NoteImportService::ImportError, "Apple Notes database schema is not supported."
  end

  def columns_for(db, table)
    @columns ||= {}
    @columns[table] ||= db.execute("PRAGMA table_info(#{quote_identifier(table)})").map { |row| row["name"] || row[1] }
  end

  def table_names(db)
    db.execute("SELECT name FROM sqlite_master WHERE type = 'table'").map { |row| row["name"] || row[0] }
  end

  def note_title_columns(db)
    columns_for(db, table_name(db)) & %w[ZTITLE1 ZTITLE ZTITLE2 ZNAME]
  end

  def note_body(row, db)
    text = first_present(row, %w[ZBODY ZTEXT ZHTMLSTRING ZSNIPPET])
    return strip_html(text) if text.present?

    notedata_body(row, db).presence || first_present(row, %w[ZSUMMARY ZSNIPPET])
  end

  def notedata_body(row, db)
    return unless row["ZNOTEDATA"].present?

    tables = table_names(db)
    return unless tables.include?("ZNOTEDATA")

    columns = columns_for(db, "ZNOTEDATA")
    text_columns = columns & %w[ZPLAINTEXT ZHTMLSTRING ZTEXT ZDATA]
    return if text_columns.empty?

    data = db.get_first_row(
      "SELECT #{text_columns.map { |column| quote_identifier(column) }.join(", ")} FROM ZNOTEDATA WHERE Z_PK = ?",
      row["ZNOTEDATA"]
    )
    return unless data

    text_columns.filter_map { |column| decode_blob(data[column]) }.find(&:present?)
  end

  def folder_name(row, db)
    folder_id = row["ZFOLDER"].presence || row["ZPARENT"].presence
    return "Unfiled" if folder_id.blank?

    table = table_name(db)
    columns = columns_for(db, table)
    title_columns = columns & %w[ZTITLE2 ZTITLE1 ZTITLE ZNAME]
    return "Unfiled" if title_columns.empty?

    folder = db.get_first_row(
      "SELECT #{title_columns.map { |column| quote_identifier(column) }.join(", ")} FROM #{quote_identifier(table)} WHERE Z_PK = ?",
      folder_id
    )
    first_present(folder || {}, title_columns).presence || "Unfiled"
  end

  def first_present(row, keys)
    keys.filter_map { |key| row[key].to_s.strip.presence }.first
  end

  def decode_blob(value)
    return if value.blank?
    return strip_html(value) if value.is_a?(String) && value.valid_encoding?

    bytes = value.to_s.b
    inflated = inflate(bytes)
    text = printable_text(inflated.presence || bytes)
    strip_html(text)
  end

  def inflate(bytes)
    Zlib::Inflate.inflate(bytes)
  rescue Zlib::DataError
    nil
  end

  def printable_text(bytes)
    bytes.to_s
         .encode("UTF-8", invalid: :replace, undef: :replace, replace: "\n")
         .scan(/[[:print:]\t ]{3,}/)
         .join("\n")
  end

  def strip_html(value)
    text = value.to_s
    return text unless text.include?("<")

    Nokogiri::HTML(text).text
  end

  def order_column(columns)
    (%w[ZMODIFICATIONDATE ZDATEEDITED ZUPDATEDAT ZCREATIONDATE Z_PK] & columns).first
  end

  def quote_identifier(value)
    %("#{value.to_s.gsub("\"", "\"\"")}")
  end
end
