require "open3"
require "cgi"

# Converts a KB document (html/docx/xlsx) into a self-contained HTML string
# suitable for rendering inside a sandboxed, script-free iframe.
class KbDocumentRenderer
  class ConversionError < StandardError; end

  def initialize(path)
    @path = path
    @ext = File.extname(path).downcase
  end

  def to_html
    case @ext
    when ".html", ".htm" then File.read(@path)
    when ".docx" then docx_html
    when ".xlsx" then xlsx_html
    else ""
    end
  end

  private

  def docx_html
    out, err, status = Open3.capture3(
      "pandoc", @path, "-f", "docx", "-t", "html", "--embed-resources", "--standalone"
    )
    raise ConversionError, "pandoc failed: #{err}" unless status.success?

    out
  rescue Errno::ENOENT
    raise ConversionError, "pandoc not available"
  end

  def xlsx_html
    xlsx = Roo::Excelx.new(@path)
    body = xlsx.sheets.map { |name| sheet_table(xlsx, name) }.join("\n")
    wrap(body)
  end

  def sheet_table(xlsx, name)
    sheet = xlsx.sheet(name)
    heading = "<h2>#{h(name)}</h2>"
    return "#{heading}<p class=\"kb-xlsx-empty\">(empty sheet)</p>" if sheet.first_row.nil?

    rows = (sheet.first_row..sheet.last_row).map do |r|
      cells = (sheet.first_column..sheet.last_column).map do |c|
        "<td>#{h(sheet.cell(r, c))}</td>"
      end.join
      "<tr>#{cells}</tr>"
    end.join

    "#{heading}<table><tbody>#{rows}</tbody></table>"
  end

  def wrap(body)
    <<~HTML
      <!doctype html>
      <html>
        <head>
          <meta charset="utf-8">
          <style>
            body { font-family: system-ui, sans-serif; margin: 1rem; color: #1a1a1a; }
            h2 { font-size: 1rem; margin: 1.25rem 0 0.5rem; }
            table { border-collapse: collapse; margin-bottom: 1rem; }
            td { border: 1px solid #d0d0d0; padding: 4px 8px; font-size: 0.85rem; }
            tr:first-child td { background: #f5f5f5; font-weight: 600; }
            .kb-xlsx-empty { color: #888; font-style: italic; }
          </style>
        </head>
        <body>#{body}</body>
      </html>
    HTML
  end

  def h(value)
    CGI.escapeHTML(value.to_s)
  end
end
