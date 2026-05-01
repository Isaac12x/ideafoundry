require "set"

module NapkinHelper
  # Returns { ref => { display: String, value: Numeric|String|nil, error: String|nil } }.
  def napkin_evaluate(data)
    return {} unless data.is_a?(Hash)
    cells = data["cells"] || {}
    calc = Dentaku::Calculator.new

    # Bind plain numeric/string cells.
    cells.each do |ref, cell|
      raw = cell["raw"].to_s
      next if raw.start_with?("=")
      val = numeric_cast(raw)
      calc.store(ref.downcase, val.nil? ? raw : val)
    end

    # Static cycle detection across formula cells.
    cyclic_refs = napkin_detect_cycles(cells)

    out = {}
    cells.each do |ref, cell|
      raw = cell["raw"].to_s
      fmt = cell["fmt"]

      if cyclic_refs.include?(ref)
        out[ref] = { display: "#CYCLE", value: nil, error: "cycle" }
        next
      end

      if raw.start_with?("=")
        expr = napkin_translate_formula(raw[1..])
        begin
          value = calc.evaluate!(expr)
          out[ref] = { display: format_napkin_cell(raw, fmt, value), value: value, error: nil }
        rescue Dentaku::ArgumentError, ::ZeroDivisionError, Dentaku::ZeroDivisionError
          out[ref] = { display: "#ERR", value: nil, error: "argument" }
        rescue Dentaku::ParseError, Dentaku::TokenizerError, Dentaku::UnboundVariableError
          out[ref] = { display: "#ERR", value: nil, error: "parse" }
        rescue Dentaku::Error => e
          msg = e.message.to_s
          if msg.match?(/cycle|recursion|stack/i)
            out[ref] = { display: "#CYCLE", value: nil, error: "cycle" }
          else
            out[ref] = { display: "#ERR", value: nil, error: "eval" }
          end
        rescue SystemStackError
          out[ref] = { display: "#CYCLE", value: nil, error: "cycle" }
        end
      else
        value = numeric_cast(raw)
        out[ref] = { display: format_napkin_cell(raw, fmt, value || raw), value: value || raw, error: nil }
      end
    end
    out
  end

  # `value` is the resolved numeric/string for the cell (formula result OR raw cast).
  # The `bold` flag in `fmt` is consumed (so style detection works) but does not wrap
  # output — bold styling is applied via CSS on the rendering cell, not inline tags.
  def format_napkin_cell(raw, fmt, value)
    parts = (fmt || "").split("|")
    parts.delete("bold")
    style = parts.first

    if value.is_a?(Numeric)
      case style
      when /\Anumber:(\d+)\z/
        format("%.#{$1.to_i}f", value)
      when /\Acurrency:([A-Z]{3}):(\d+)\z/
        symbol = currency_symbol($1)
        "#{symbol}#{number_with_delimiter_and_precision(value, $2.to_i)}"
      when /\Apercent:(\d+)\z/
        "#{format("%.#{$1.to_i}f", value * 100.0)}%"
      else
        # Auto: integers without decimals, floats trimmed of trailing zeros.
        value.is_a?(Integer) ? value.to_s : trim_trailing_zeros(format("%.10f", value))
      end
    else
      raw
    end
  end

  private

  def numeric_cast(s)
    return nil if s.nil? || s.empty?
    Float(s)
  rescue ArgumentError, TypeError
    nil
  end

  # Build a dependency graph from formula cells and return the set of refs
  # that participate in a cycle (including self-references).
  def napkin_detect_cycles(cells)
    deps = {}
    cells.each do |ref, cell|
      raw = cell["raw"].to_s
      next unless raw.start_with?("=")
      deps[ref] = napkin_extract_refs(raw[1..], cells.keys)
    end

    cyclic = Set.new
    deps.each_key do |ref|
      visited = {}
      stack = []
      detect = lambda do |node|
        state = visited[node]
        if state == :visiting
          # Mark all nodes in the current path back to `node` as cyclic.
          idx = stack.index(node)
          stack[idx..].each { |n| cyclic << n } if idx
          return true
        end
        return false if state == :done
        visited[node] = :visiting
        stack.push(node)
        (deps[node] || []).each { |child| detect.call(child) }
        stack.pop
        visited[node] = :done
        false
      end
      detect.call(ref)
    end
    cyclic
  end

  # Extract uppercase A1-style refs from a formula expression, expanding A1:A3 ranges.
  def napkin_extract_refs(expr, valid_refs)
    found = []
    expr.scan(/\b([A-Z])(\d+):([A-Z])(\d+)\b/) do |c1, r1, c2, r2|
      (c1..c2).each { |c| (r1.to_i..r2.to_i).each { |r| found << "#{c}#{r}" } }
    end
    # Then strip ranges so single-ref scan doesn't double-count.
    stripped = expr.gsub(/\b[A-Z]\d+:[A-Z]\d+\b/, "")
    stripped.scan(/\b([A-Z]\d+)\b/) { |m| found << m[0] }
    found.uniq & valid_refs
  end

  # Dentaku uses lowercase identifiers; expand A1:A3 → a1,a2,a3 then downcase A1 → a1.
  def napkin_translate_formula(expr)
    expanded = expr.gsub(/\b([A-Z])(\d+):([A-Z])(\d+)\b/) do
      c1, r1, c2, r2 = $1, $2.to_i, $3, $4.to_i
      refs = []
      (c1..c2).each { |c| (r1..r2).each { |r| refs << "#{c.downcase}#{r}" } }
      refs.join(",")
    end
    expanded.gsub(/\b([A-Z])(\d+)\b/) { "#{$1.downcase}#{$2}" }
  end

  def number_with_delimiter_and_precision(value, decimals)
    int, dec = format("%.#{decimals}f", value).split(".")
    int_with_commas = int.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    dec ? "#{int_with_commas}.#{dec}" : int_with_commas
  end

  def trim_trailing_zeros(s)
    return s unless s.include?(".")
    s.sub(/0+\z/, "").sub(/\.\z/, "")
  end

  def currency_symbol(code)
    { "USD" => "$", "EUR" => "€", "GBP" => "£", "JPY" => "¥" }.fetch(code, "#{code} ")
  end
end
