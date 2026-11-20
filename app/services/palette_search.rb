# Text ranking for the command palette's Similar and Deep modes. No embeddings in the app, so
# Similar is TF-IDF cosine over a small corpus and Deep is an all-terms scan with snippets.
# ponytail: a true semantic search needs a local embedding endpoint + vector store (sqlite-vec); swap `similar` for a cosine over stored vectors.
module PaletteSearch
  STOP = %w[the and for are but not you all any can had her was one our out has have this that with from they will what when your their there about which would into than then them these some]
  SNIPPET = 70

  module_function

  def terms(text) = text.to_s.downcase.scan(/[[:alnum:]]{3,}/).reject { |w| STOP.include?(w) }

  # docs: [{ text:, ... }]; returns docs with :score > 0, best first. The seed's own doc is the caller's to exclude.
  def similar(seed_text, docs, limit: 8)
    seed = terms(seed_text).tally
    return [] if seed.empty?

    toks = docs.map { |d| terms(d[:text]).tally }
    df = Hash.new(0)
    toks.each { |t| t.each_key { |w| df[w] += 1 } }
    idf = ->(w) { Math.log((docs.size + 1.0) / (df[w] + 1)) + 1 }
    vec = ->(t) { t.to_h { |w, c| [ w, (1 + Math.log(c)) * idf.(w) ] } }
    norm = ->(v) { Math.sqrt(v.values.sum { |x| x * x }) }
    sv = vec.(seed)
    sn = norm.(sv)
    scored = docs.each_with_index.filter_map do |d, i|
      dv = vec.(toks[i])
      dot = sv.sum { |w, x| x * (dv[w] || 0) }
      next unless dot.positive?

      d.merge(score: dot / (sn * norm.(dv)))
    end
    scored.sort_by { |d| -d[:score] }.first(limit)
  end

  # Occurrences of every query word in text, or 0 unless all are present.
  def deep_score(text, words)
    down = text.to_s.downcase
    counts = words.map { |w| down.scan(w).size }
    counts.all?(&:positive?) ? counts.sum : 0
  end

  # ~SNIPPET chars either side of the first hit, whitespace squished.
  def snippet(text, words)
    flat = text.to_s.squish
    at = words.filter_map { |w| flat.downcase.index(w) }.min || 0
    from = [ at - SNIPPET, 0 ].max
    "#{'…' if from.positive?}#{flat[from, SNIPPET * 2]}#{'…' if from + SNIPPET * 2 < flat.size}"
  end
end
