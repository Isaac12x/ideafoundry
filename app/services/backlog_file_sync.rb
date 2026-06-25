# Mirrors a user's backlog to a human-editable Markdown file and re-imports
# external edits, keeping DB and file in sync (two-way).
#
# Format (round-trippable):
#
#   # Backlog
#
#   ## [ ] Title   <!-- id:12 pin:1 -->
#   notes paragraph...
#   - [ ] subitem
#   - [x] done subitem
#
#   Links:
#   - Label — https://example.com
#
#   ## [x] Completed item   <!-- id:9 -->
#
# The item body (between the heading and an optional "Links:" section) is the
# description verbatim. The heading checkbox is `completed`; the trailing HTML
# comment carries `id` and `pin`. Order in the file is the position order.
class BacklogFileSync
  HEADING = /\A##\s+\[(?<state>[ xX])\]\s+(?<title>.*?)(?:\s*<!--(?<attrs>.*?)-->)?\s*\z/
  LINKS_HEADER = /\ALinks:\s*\z/
  LINK_LINE = /\A-\s+(?:(?<label>.*?)\s+[—-]\s+)?(?<url>\S+)\s*\z/

  def self.path
    custom = Rails.application.config.x.backlog_backup_path
    return custom if custom.is_a?(String) && custom.present?

    Rails.root.join("storage", "backlog.md")
  end

  def self.export(user)
    new(user).export
  end

  def self.import(user)
    new(user).import
  end

  # Re-import external edits if the file diverges from the canonical render,
  # then rewrite the canonical file so DB and file are byte-identical.
  def self.sync_from_file(user)
    file = path
    return unless File.exist?(file)

    on_disk = File.read(file)
    return if on_disk == new(user).render # already in sync — avoid import/export loop

    new(user).import(on_disk)
    export(user)
  end

  def initialize(user)
    @user = user
  end

  def render
    blocks = ordered_items.map { |item| render_item(item) }
    (["# Backlog", ""] + blocks).join("\n").rstrip + "\n"
  end

  def export
    file = self.class.path
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, render)
  rescue SystemCallError => e
    Rails.logger.warn("BacklogFileSync export failed: #{e.message}")
  end

  def import(content = File.read(self.class.path))
    parsed = parse(content)
    existing = @user.build_items.index_by(&:id)
    seen = []

    parsed.each_with_index do |attrs, index|
      item = attrs[:id] && existing[attrs[:id]]
      if item
        apply!(item, attrs, index + 1)
        seen << item.id
      else
        created = @user.build_items.create(creation_attrs(attrs, index + 1))
        seen << created.id if created.persisted?
      end
    end

    # Items previously synced but now absent from the file are archived, not
    # destroyed (soft-delete).
    existing.each_value do |item|
      item.archive! unless seen.include?(item.id) || item.completed?
    end
  end

  private

  def ordered_items
    @user.build_items.pending.to_a + @user.build_items.done.to_a
  end

  def render_item(item)
    lines = []
    attrs = ["id:#{item.id}"]
    attrs << "pin:1" if item.pinned?
    lines << "## [#{item.completed? ? 'x' : ' '}] #{item.title}   <!-- #{attrs.join(' ')} -->"
    body = item.description.to_s.rstrip
    lines << body if body.present?

    if item.links.any?
      lines << ""
      lines << "Links:"
      item.links.each do |link|
        label = link["label"].presence
        lines << (label ? "- #{label} — #{link['url']}" : "- #{link['url']}")
      end
    end

    lines << ""
    lines.join("\n")
  end

  def parse(content)
    items = []
    current = nil
    section = :body

    content.to_s.each_line(chomp: true) do |line|
      if (m = line.match(HEADING))
        items << current if current
        current = { completed: m[:state].match?(/x/i), title: m[:title].strip,
                    body: [], links: [] }.merge(parse_attrs(m[:attrs]))
        section = :body
      elsif current.nil?
        next # skip preamble (e.g. "# Backlog")
      elsif line.match?(LINKS_HEADER)
        section = :links
      elsif section == :links && (lm = line.match(LINK_LINE))
        current[:links] << { "url" => lm[:url], "label" => lm[:label].to_s.strip }
      else
        current[:body] << line
      end
    end
    items << current if current

    items.each { |i| i[:description] = i[:body].join("\n").strip }
    items
  end

  def parse_attrs(attrs)
    out = {}
    return out if attrs.blank?

    out[:id] = Regexp.last_match(1).to_i if attrs =~ /id:(\d+)/
    out[:pinned] = true if attrs =~ /pin:1/
    out
  end

  def apply!(item, attrs, position)
    item.title = attrs[:title]
    item.description = attrs[:description]
    item.links = attrs[:links]
    item.pinned = attrs.fetch(:pinned, false)
    item.position = position
    # Coerce completion to pending if the checklist would block it.
    item.completed = attrs[:completed] && !item.checklist_blocking_completion?
    item.completed_at = item.completed? ? (item.completed_at || Time.current) : nil
    item.save
  end

  def creation_attrs(attrs, position)
    will_block = BuildItem.new(description: attrs[:description]).checklist_blocking_completion?
    {
      title: attrs[:title],
      description: attrs[:description],
      links: attrs[:links],
      pinned: attrs.fetch(:pinned, false),
      position: position,
      completed: attrs[:completed] && !will_block,
      completed_at: (attrs[:completed] && !will_block) ? Time.current : nil
    }
  end
end
