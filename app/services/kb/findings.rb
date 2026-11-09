module Kb
  # Discrete findings stored under `findings` in a node's yml (not in FIELDS).
  # Mixed into YamlNode subclasses (project, test).
  module Findings
    MAX_FINDING = 2000

    # [{"id", "text", "at"}], malformed entries dropped.
    def findings = read_items("findings")

    # Same shape under "ideas": things to try, kept while working (project only).
    def ideas = read_items("ideas")

    def add_idea!(text)
      item = { "id" => SecureRandom.hex(4), "text" => clean_finding(text), "at" => Date.current.iso8601 }
      write_items!("ideas", ideas + [ item ])
      item
    end

    def remove_idea!(id)
      list = ideas.reject { |f| f["id"] == id.to_s }
      raise ArgumentError, "Idea not found." if list.size == ideas.size

      write_items!("ideas", list)
      self
    end

    def read_items(key)
      Array(meta[key]).filter_map do |item|
        next unless item.is_a?(Hash) && item["id"].present? && item["text"].to_s.strip.present?

        { "id" => item["id"].to_s, "text" => item["text"].to_s, "at" => item["at"].to_s }
      end
    end

    def add_finding!(text)
      item = { "id" => SecureRandom.hex(4), "text" => clean_finding(text), "at" => Date.current.iso8601 }
      write_findings!(findings + [ item ])
      item
    end

    def update_finding!(id, text)
      text = clean_finding(text)
      item = nil
      list = findings.map { |f| f["id"] == id.to_s ? (item = f.merge("text" => text)) : f }
      raise ArgumentError, "Finding not found." unless item

      write_findings!(list)
      item
    end

    def remove_finding!(id)
      list = findings.reject { |f| f["id"] == id.to_s }
      raise ArgumentError, "Finding not found." if list.size == findings.size

      write_findings!(list)
      self
    end

    private

    def clean_finding(text)
      text = text.to_s.strip.first(MAX_FINDING)
      raise ArgumentError, "Finding can't be blank." if text.blank?

      text
    end

    def write_findings!(list) = write_items!("findings", list)

    def write_items!(key, list)
      write_meta!(meta.merge(key => list))
      @meta = nil
    end
  end
end
