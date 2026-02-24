module TemplatesHelper
  def format_custom_field_value(value, type)
    return content_tag(:span, "—", class: "text-muted") if value.blank?

    case type
    when 'boolean'
      value.to_s == 'true' ? 'Yes' : 'No'
    when 'date'
      begin
        Date.parse(value.to_s).strftime("%B %d, %Y")
      rescue
        value
      end
    when 'textarea'
      simple_format(value.to_s)
    else
      value.to_s
    end
  end
end
