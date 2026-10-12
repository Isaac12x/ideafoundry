# A spreadsheet of potential licensors uploaded against one idea. The original
# file is kept (Active Storage) alongside the column mapping the user chose, so
# an import can be reviewed or re-run later without re-uploading.
class LicensorImport < ApplicationRecord
  belongs_to :idea
  has_one_attached :file

  serialize :column_mapping, coder: JSON

  # Licensor attributes a spreadsheet column can be mapped onto.
  FIELDS = %w[company contact_name contact_email contact_url next_action notes stage].freeze

  FIELD_LABELS = {
    "company"       => "Company",
    "contact_name"  => "Contact name",
    "contact_email" => "Email",
    "contact_url"   => "Website / URL",
    "next_action"   => "Next action",
    "notes"         => "Notes",
    "stage"         => "Stage"
  }.freeze

  # Header text that should auto-map to a field, matched loosely (see .guess_field).
  FIELD_HINTS = {
    "company"       => %w[company organisation organization licensor account name firm publisher studio],
    "contact_name"  => [ "contact", "contact name", "person", "full name", "first name", "owner", "rep" ],
    "contact_email" => %w[email e-mail mail],
    "contact_url"   => %w[url website site web link domain],
    "next_action"   => [ "next action", "next step", "action", "todo", "follow up", "followup" ],
    "notes"         => %w[notes note comment comments description remarks],
    "stage"         => %w[stage status pipeline phase]
  }.freeze

  STATUSES = %w[pending imported].freeze

  validates :filename, presence: true
  validates :status, inclusion: { in: STATUSES }
  validate  :file_must_be_attached
  validate  :file_must_be_supported
  validate  :file_must_be_small_enough

  scope :recent, -> { order(created_at: :desc) }

  SUPPORTED_EXTENSIONS = %w[.csv .tsv .xlsx .xlsm].freeze
  MAX_FILE_SIZE = 10.megabytes

  def extension
    File.extname(filename.to_s).downcase
  end

  def imported?
    status == "imported"
  end

  def mapping
    (column_mapping || {}).select { |_index, field| FIELDS.include?(field.to_s) }
  end

  # Field => column index, for the columns the user actually mapped.
  def field_columns
    mapping.each_with_object({}) { |(index, field), acc| acc[field.to_s] = index.to_i }
  end

  def mapped_company_column
    field_columns["company"]
  end

  def self.field_label(field)
    FIELD_LABELS[field.to_s] || field.to_s.humanize
  end

  # Best-guess field for a spreadsheet header, or nil when nothing matches.
  # Exact hits win over substring hits so "Company email" maps to email, not company.
  def self.guess_field(header)
    text = header.to_s.downcase.strip.gsub(/[_\-]+/, " ").squeeze(" ")
    return nil if text.blank?

    FIELDS.find { |field| FIELD_HINTS[field].include?(text) } ||
      FIELDS.find { |field| FIELD_HINTS[field].any? { |hint| text.include?(hint) } }
  end

  private

  def file_must_be_attached
    errors.add(:file, "must be attached") unless file.attached?
  end

  def file_must_be_supported
    return if extension.in?(SUPPORTED_EXTENSIONS)

    errors.add(:file, "must be a CSV, TSV or Excel (.xlsx) file")
  end

  def file_must_be_small_enough
    return unless file.attached?
    return if file.byte_size <= MAX_FILE_SIZE

    errors.add(:file, "must be smaller than #{MAX_FILE_SIZE / 1.megabyte} MB")
  end
end
