# Turns a mapped LicensorImport into Licensor records on its idea.
# Re-running an import is safe: rows already present (same company + email)
# are skipped rather than duplicated.
class LicensorImporter
  Result = Struct.new(:created, :skipped, :invalid_emails, keyword_init: true) do
    def summary
      parts = ["#{created} #{'licensor'.pluralize(created)} imported"]
      parts << "#{skipped} skipped as duplicates" if skipped.positive?
      parts << "#{invalid_emails} #{'email'.pluralize(invalid_emails)} dropped as unreadable" if invalid_emails.positive?
      parts.to_sentence + "."
    end
  end

  class << self
    def call(import, grid)
      new(import, grid).call
    end
  end

  def initialize(import, grid)
    @import = import
    @idea = import.idea
    @grid = grid
    @columns = import.field_columns
  end

  def call
    result = Result.new(created: 0, skipped: 0, invalid_emails: 0)
    seen = existing_keys

    data_rows.each do |row|
      attributes = attributes_for(row)
      next if attributes[:company].blank?

      # Drop the email before keying, so the key matches what actually gets
      # stored and a re-run recognises the row it created last time.
      result.invalid_emails += 1 if drop_invalid_email!(attributes)

      key = dedupe_key(attributes)
      if seen.include?(key)
        result.skipped += 1
        next
      end

      # ponytail: one INSERT per row (plus the model's position lookup). Fine at
      # spreadsheet scale; batch it if imports ever run to tens of thousands.
      @idea.licensors.create!(attributes)
      seen << key
      result.created += 1
    end

    @import.update!(status: "imported", imported_count: result.created, row_count: data_rows.size)
    result
  end

  private

  def data_rows
    @data_rows ||= @import.headers_in_first_row? ? @grid.rows.drop(1) : @grid.rows
  end

  def attributes_for(row)
    LicensorImport::FIELDS.each_with_object({}) do |field, attrs|
      index = @columns[field]
      next if index.nil?

      value = row[index].to_s.strip
      attrs[field.to_sym] = value
    end.tap do |attrs|
      attrs[:stage] = normalize_stage(attrs[:stage])
    end
  end

  # Accepts the enum key ("closed_won"), our label ("Closed — Won") or anything
  # that humanizes to the same thing; unknown values start at the top of the funnel.
  def normalize_stage(value)
    text = value.to_s.downcase.strip
    return "identified" if text.blank?

    Licensor::STAGE_ORDER.find { |stage| stage == text.tr(" -", "__") } ||
      Licensor::STAGE_ORDER.find { |stage| Licensor.stage_label(stage).downcase == text } ||
      Licensor::STAGE_ORDER.find { |stage| stage.tr("_", " ") == text } ||
      "identified"
  end

  # Licensor validates email format, and one bad cell should not fail the row.
  def drop_invalid_email!(attributes)
    email = attributes[:contact_email]
    return false if email.blank? || email.match?(URI::MailTo::EMAIL_REGEXP)

    attributes[:notes] = [attributes[:notes], "Imported email: #{email}"].compact_blank.join("\n")
    attributes[:contact_email] = ""
    true
  end

  def existing_keys
    @idea.licensors.pluck(:company, :contact_email)
         .map { |company, email| dedupe_key(company: company, contact_email: email) }
         .to_set
  end

  def dedupe_key(attributes)
    [attributes[:company].to_s.downcase.strip, attributes[:contact_email].to_s.downcase.strip]
  end
end
