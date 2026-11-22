# The built-in patent Reference: curated Patent Notes in app/content/patents/<cluster>/<slug>.md
# (YAML front matter + Markdown body). Read-only, shipped with the app; see docs/plans/patent-reference.md.
class PatentReference
  ROOT = Rails.root.join("app/content/patents")
  CLUSTERS = {
    "claims" => "Claims & eligibility", "specification" => "Specification & format", "drawings" => "Drawings",
    "provisional" => "Provisional & priority", "prior-art" => "Prior art (102/103)", "prosecution" => "Prosecution",
    "portfolio" => "Portfolio & strategy", "workflows" => "Workflows"
  }.freeze

  STOP = %w[the and for how what why when does with this that are can you your from into about which should would].to_set.freeze

  Note = Data.define(:slug, :title, :cluster, :jurisdiction, :aliases, :related, :sources, :corrections, :links, :body) do
    def cluster_label = CLUSTERS.fetch(cluster, cluster)
    def from_sources? = sources != [ "not from sources" ]
    # Plain-text teaser: first lines without headings/markdown syntax.
    def summary
      text = body.to_s.gsub(/^\s*#.*$/, "").gsub(/\[([^\]]+)\]\([^)]*\)/, '\\1').gsub(/[*_`>]|^\s*(?:\d+\.|-)\s+/, "")
      text.squish.truncate(160)
    end
  end

  class << self
    def all = notes.values
    def find(slug) = notes[slug.to_s]
    def by_cluster = all.group_by(&:cluster).sort_by { |c, _| CLUSTERS.keys.index(c) || 99 }

    # ponytail: naive term scoring over ~100 short notes; route through SemanticIndex if the set grows.
    def search(query, limit: 5)
      words = query.to_s.downcase.scan(/[a-z0-9]+/).reject { |w| w.size < 3 || STOP.include?(w) }
      return [] if words.empty?

      phrase = query.to_s.downcase.strip
      scored = all.map do |n|
        names = ([ n.title, n.slug.tr("-", " ") ] + n.aliases).map(&:downcase)
        text = n.body.downcase
        score = names.any? { |name| name == phrase } ? 100 : 0
        score += words.sum { |w| (names.any? { |name| name.include?(w) } ? 10 : 0) + [ text.scan(w).size, 5 ].min }
        [ n, score ]
      end
      scored.select { |_, s| s.positive? }.sort_by { |n, s| [ -s, n.title ] }.first(limit).map(&:first)
    end

    # ponytail: keyword gate for "is this thread about patents"; classifier if it misfires.
    TOPIC = /\b(patent\w*|claims?|prior[- ]art|uspto|provisional|non-provisional|pct|prosecution|office action|infring\w*|novelty|obviousness|enablement|§ ?1\d\d)\b/i
    def topic?(text) = text.to_s.match?(TOPIC)

    # Markdown block of the top notes for a prompt, or nil when the text isn't about patents.
    def context_for(text, limit: 3)
      return unless topic?(text)
      notes = search(text, limit: limit).presence or return
      notes.map { |n| "### #{n.title} [[note:#{n.slug}]]\n#{n.body.strip}" }.join("\n\n")
    end

    def reload! = @notes = nil

    private

    def notes
      return load_notes unless Rails.env.production? # pick up content edits without a restart
      @notes ||= load_notes
    end

    def load_notes
      Dir.glob(ROOT.join("*/*.md")).sort.to_h do |path|
        meta, body = parse(File.read(path))
        note = Note.new(
          slug: meta.fetch("slug"), title: meta.fetch("title"), cluster: meta.fetch("cluster"),
          jurisdiction: meta["jurisdiction"].presence || "US", aliases: Array(meta["aliases"]).map(&:to_s),
          related: Array(meta["related"]).map(&:to_s), sources: Array(meta["sources"]).map(&:to_s),
          corrections: Array(meta["corrections"]).map(&:to_s), links: Array(meta["links"]).map(&:to_s), body: body
        )
        [ note.slug, note ]
      end
    end

    def parse(raw)
      match = raw.match(/\A---\s*\n(.*?)\n---\s*\n(.*)\z/m) or raise ArgumentError, "missing front matter"
      [ YAML.safe_load(match[1]) || {}, match[2] ]
    end
  end
end
