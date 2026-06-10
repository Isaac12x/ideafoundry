require "digest"
require "json"
require "securerandom"
require "stringio"
require "zip"

class NoteImportService
  class ImportError < StandardError; end

  MAX_NOTES = 1_000
  MAX_NOTE_CHARACTERS = 120_000
  SUPPORTED_EXTENSIONS = %w[.enex .htm .html .json .markdown .md .txt .zip].freeze

  SOURCE_OPTIONS = {
    "apple_notes" => "Apple Notes",
    "notion" => "Notion",
    "google_keep" => "Google Keep",
    "evernote" => "Evernote"
  }.freeze

  Folder = Struct.new(:key, :name, :count, keyword_init: true)

  Preview = Struct.new(:source, :source_label, :batch_id, :folders, :notes, :payload, keyword_init: true) do
    def total_notes
      notes.size
    end

    def encoded_payload
      NoteImportService.encode_payload(payload)
    end
  end

  Result = Struct.new(:source, :source_label, :batch_id, :imported_count, :folder_count, keyword_init: true)

  class << self
    def source_options
      SOURCE_OPTIONS
    end

    def source_label_for(source)
      SOURCE_OPTIONS.fetch(source)
    end

    def encode_payload(payload)
      verifier.generate(payload)
    end

    def import!(user:, payload:, selected_folder_keys:)
      data = verifier.verify(payload.to_s)
      selected_keys = Array(selected_folder_keys).map(&:to_s).reject(&:blank?).uniq
      raise ImportError, "Select at least one folder to import." if selected_keys.empty?

      source = normalize_source!(data["source"])
      source_label = source_label_for(source)
      notes = Array(data["notes"]).select do |note|
        (Array(note["folder_keys"]) & selected_keys).any?
      end
      raise ImportError, "No notes matched the selected folders." if notes.empty?

      batch_id = data["batch_id"].presence || SecureRandom.uuid
      matched_folder_count = notes.flat_map { |note| Array(note["folder_keys"]) & selected_keys }.uniq.size

      ActiveRecord::Base.transaction do
        notes.each do |note|
          IntakeSubmissionService.new(
            user: user,
            title: note["title"],
            body: note["body"],
            source: source,
            source_reference: "#{batch_id}:#{note["import_index"]}",
            raw_payload: raw_payload_for(note, source:, source_label:, batch_id:)
          ).call
        end
      end

      Result.new(
        source: source,
        source_label: source_label,
        batch_id: batch_id,
        imported_count: notes.size,
        folder_count: matched_folder_count
      )
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise ImportError, "Import preview expired or could not be verified."
    end

    private

    def verifier
      Rails.application.message_verifier(:note_imports)
    end

    def raw_payload_for(note, source:, source_label:, batch_id:)
      {
        "import" => {
          "batch_id" => batch_id,
          "source" => source,
          "source_label" => source_label,
          "folders" => Array(note["folders"]),
          "source_path" => note["source_path"]
        },
        "metadata" => note["metadata"].presence
      }.compact
    end
  end

  def self.normalize_source!(source)
    source = source.to_s
    return source if SOURCE_OPTIONS.key?(source)

    raise ImportError, "Choose a supported note app."
  end

  def initialize(source:, files:)
    @source = self.class.normalize_source!(source)
    @files = Array(files).reject(&:blank?)
  end

  def preview
    raise ImportError, "Choose at least one export file or folder." if files.empty?

    notes = expanded_entries.flat_map { |entry| parse_entry(entry) }.compact
    notes = notes.first(MAX_NOTES)
    raise ImportError, "No supported notes were found in that import." if notes.empty?

    batch_id = SecureRandom.uuid
    notes = notes.each_with_index.map { |note, index| note.merge("import_index" => index) }
    payload = {
      "source" => source,
      "source_label" => source_label,
      "batch_id" => batch_id,
      "notes" => notes
    }

    Preview.new(
      source: source,
      source_label: source_label,
      batch_id: batch_id,
      folders: build_folders(notes),
      notes: notes,
      payload: payload
    )
  end

  private

  Entry = Struct.new(:path, :content, :content_type, keyword_init: true)

  attr_reader :files, :source

  def source_label
    self.class.source_label_for(source)
  end

  def expanded_entries
    files.flat_map do |file|
      filename = upload_filename(file)
      content = upload_content(file)
      next [] if filename.blank? || content.blank?

      if File.extname(filename).downcase == ".zip"
        expand_zip(filename, content)
      else
        [Entry.new(path: filename, content: content, content_type: upload_content_type(file))]
      end
    end
  end

  def upload_filename(file)
    if file.respond_to?(:original_filename)
      file.original_filename.to_s
    elsif file.respond_to?(:path)
      File.basename(file.path.to_s)
    else
      ""
    end
  end

  def upload_content(file)
    file.rewind if file.respond_to?(:rewind)
    file.respond_to?(:read) ? file.read.to_s : ""
  ensure
    file.rewind if file.respond_to?(:rewind)
  end

  def upload_content_type(file)
    file.respond_to?(:content_type) ? file.content_type.to_s : nil
  end

  def expand_zip(filename, content)
    entries = []

    Zip::File.open_buffer(StringIO.new(content)) do |zip|
      zip.each do |entry|
        next if entry.directory?
        next if ignored_path?(entry.name)
        next unless supported_entry?(entry.name)

        entries << Entry.new(
          path: entry.name,
          content: entry.get_input_stream.read,
          content_type: "application/octet-stream"
        )
      end
    end

    entries
  rescue Zip::Error
    raise ImportError, "#{filename} is not a readable ZIP export."
  end

  def parse_entry(entry)
    return [] if ignored_path?(entry.path)
    return [] unless supported_entry?(entry.path)

    case File.extname(entry.path).downcase
    when ".enex"
      parse_enex(entry)
    when ".htm", ".html"
      [parse_html(entry)]
    when ".json"
      parse_json(entry)
    when ".markdown", ".md", ".txt"
      [parse_text(entry)]
    else
      []
    end
  end

  def supported_entry?(path)
    SUPPORTED_EXTENSIONS.include?(File.extname(path.to_s).downcase)
  end

  def ignored_path?(path)
    parts = path.to_s.split(/[\/\\]/)
    parts.any? { |part| part.blank? || part == "__MACOSX" || part.start_with?(".") }
  end

  def parse_text(entry)
    body = normalize_body(entry.content)
    title = markdown_title(body).presence || clean_title(File.basename(entry.path, ".*"))

    build_note(
      title: title,
      body: body,
      folders: [folder_from_path(entry.path)],
      source_path: entry.path
    )
  end

  def parse_html(entry)
    doc = Nokogiri::HTML(entry.content)
    doc.css("script, style").remove

    title = html_title(doc).presence || clean_title(File.basename(entry.path, ".*"))
    body_node = doc.at("body") || doc
    body_node.css("br").each { |br| br.replace("\n") }

    build_note(
      title: title,
      body: normalize_body(body_node.text),
      folders: [folder_from_path(entry.path)],
      source_path: entry.path
    )
  end

  def parse_json(entry)
    extract_json_notes(JSON.parse(entry.content), entry.path)
  rescue JSON::ParserError
    []
  end

  def extract_json_notes(value, path)
    case value
    when Array
      value.flat_map { |item| extract_json_notes(item, path) }
    when Hash
      if json_note_hash?(value)
        [build_json_note(value, path)]
      else
        value.values.flat_map { |item| extract_json_notes(item, path) }
      end
    else
      []
    end
  end

  def json_note_hash?(value)
    value.key?("textContent") ||
      value.key?("listContent") ||
      value.key?("content") ||
      value.key?("body") ||
      value.key?("note")
  end

  def build_json_note(value, path)
    title = value["title"].presence || value["name"].presence || clean_title(File.basename(path, ".*"))
    body = [
      value["textContent"],
      value["content"],
      value["body"],
      value["note"],
      json_list_content(value["listContent"])
    ].compact_blank.join("\n\n")

    labels = json_labels(value)
    folders = labels.presence || [folder_from_path(path)]

    build_note(
      title: title,
      body: body,
      folders: folders,
      source_path: path,
      metadata: json_metadata(value)
    )
  end

  def json_list_content(value)
    Array(value).filter_map do |item|
      if item.is_a?(Hash)
        item["text"].presence || item["textContent"].presence || item["title"].presence
      else
        item.to_s.presence
      end
    end.join("\n")
  end

  def json_labels(value)
    Array(value["labels"]).filter_map do |label|
      case label
      when Hash
        label["name"].presence || label["title"].presence
      else
        label.to_s.presence
      end
    end
  end

  def json_metadata(value)
    value.slice(
      "createdTimestampUsec",
      "userEditedTimestampUsec",
      "isArchived",
      "isPinned",
      "color"
    )
  end

  def parse_enex(entry)
    doc = Nokogiri::XML(entry.content)
    notebook = folder_from_path(entry.path, fallback: clean_title(File.basename(entry.path, ".*")))

    doc.xpath("//note").map do |node|
      title = node.at_xpath("title")&.text.presence || clean_title(File.basename(entry.path, ".*"))
      enml = node.at_xpath("content")&.text.to_s
      content_doc = Nokogiri::HTML(enml)
      content_doc.css("script, style").remove
      tags = node.xpath("tag").map { |tag| tag.text.strip }.reject(&:blank?)

      build_note(
        title: title,
        body: normalize_body(content_doc.text),
        folders: [notebook],
        source_path: entry.path,
        metadata: {
          "created" => node.at_xpath("created")&.text.presence,
          "updated" => node.at_xpath("updated")&.text.presence,
          "tags" => tags.presence
        }.compact
      )
    end
  end

  def build_note(title:, body:, folders:, source_path:, metadata: {})
    normalized_body = normalize_body(body)
    return if title.blank? && normalized_body.blank?

    folder_names = Array(folders).filter_map { |folder| normalize_folder_name(folder) }.presence || ["Unfiled"]

    {
      "title" => clean_title(title.presence || body_title(normalized_body) || source_path),
      "body" => normalized_body,
      "folder" => folder_names.first,
      "folders" => folder_names,
      "folder_keys" => folder_names.map { |folder| folder_key(folder) },
      "source_path" => source_path,
      "metadata" => metadata
    }
  end

  def build_folders(notes)
    counts = Hash.new(0)
    names = {}

    notes.each do |note|
      Array(note["folders"]).zip(Array(note["folder_keys"])).each do |name, key|
        next if key.blank?

        names[key] = name
        counts[key] += 1
      end
    end

    counts.map { |key, count| Folder.new(key: key, name: names[key], count: count) }
          .sort_by { |folder| folder.name.downcase }
  end

  def folder_from_path(path, fallback: "Unfiled")
    dirname = File.dirname(path.to_s)
    parts = dirname.split(/[\/\\]/).reject { |part| part.blank? || part == "." || part == "__MACOSX" }
    normalize_folder_name(parts.presence&.join(" / ") || fallback)
  end

  def normalize_folder_name(folder)
    folder.to_s.gsub(/\s+/, " ").strip.presence || "Unfiled"
  end

  def folder_key(folder)
    Digest::SHA256.hexdigest(folder.to_s.downcase)[0, 16]
  end

  def markdown_title(body)
    body.to_s.lines.find { |line| line.match?(/\A\s{0,3}#\s+\S/) }&.sub(/\A\s{0,3}#\s+/, "")&.strip
  end

  def html_title(doc)
    doc.at("title")&.text&.strip.presence || doc.at("h1")&.text&.strip
  end

  def body_title(body)
    body.to_s.lines.map(&:strip).find(&:present?)
  end

  def clean_title(value)
    value.to_s
         .sub(/\s+[0-9a-f]{32}\z/i, "")
         .tr("_", " ")
         .gsub(/\s+/, " ")
         .strip
         .presence || "Untitled imported note"
  end

  def normalize_body(value)
    text = value.to_s.encode("UTF-8", invalid: :replace, undef: :replace, replace: "")
    text = text.gsub(/\r\n?/, "\n")
               .gsub(/[ \t]+\n/, "\n")
               .gsub(/\n{4,}/, "\n\n\n")
               .strip

    return text if text.length <= MAX_NOTE_CHARACTERS

    "#{text[0, MAX_NOTE_CHARACTERS]}\n\n[Truncated during import preview.]"
  end
end
