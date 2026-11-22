# Presentation helpers for the Patent Reference.
module ReferenceHelper
  # => [label, host] for an official-source URL, e.g. ["MPEP § 2111", "uspto.gov"].
  def reference_source_label(url)
    uri = URI.parse(url.to_s)
    host = uri.host.to_s.delete_prefix("www.")
    path = CGI.unescape(uri.path.to_s)
    frag = uri.fragment.to_s
    [ source_label_for(host, path, frag, uri.query.to_s), host ]
  rescue URI::InvalidURIError
    [ url.to_s.truncate(60), "" ]
  end

  # Notes in the same cluster, alphabetical, around the given one.
  def reference_neighbors(note)
    sibs = PatentReference.all.select { |n| n.cluster == note.cluster }.sort_by(&:title)
    i = sibs.index { |n| n.slug == note.slug }
    i ? [ (sibs[i - 1] if i.positive?), sibs[i + 1] ] : [ nil, nil ]
  end

  private

  # Hand-named landing pages; everything else is derived from the URL shape.
  NAMED_SOURCES = {
    "globaldossier.uspto.gov" => "Global Dossier", "patentcenter.uspto.gov" => "Patent Center",
    "ppubs.uspto.gov" => "Patent Public Search", "/web/offices/pac/mpep" => "MPEP (full manual)",
    "/patents/apply" => "Applying for patents", "/patents/basics" => "Patent basics", "/patents/maintain" => "Maintenance fees",
    "/patents/apply/forms" => "Patent forms", "/patents/apply/patent-center" => "Patent Center (about)", "/web/patents/classification/cpc/html/cpc.html" => "CPC classification scheme",
    "/learning-and-resources/fees-and-payment/uspto-fee-schedule" => "USPTO fee schedule",
    "/initiatives/artificial-intelligence" => "USPTO AI guidance"
  }.freeze

  def source_label_for(host, path, frag, query)
    path = path.delete_suffix("/")
    return NAMED_SOURCES[host] || NAMED_SOURCES[path] if NAMED_SOURCES[host] || NAMED_SOURCES[path]

    if path.include?("/mpep")
      return "MPEP ch. #{$1}" if path =~ /mpep-(\d+)\.html/
      return "MPEP § #{$1}" if path =~ %r{/s([\d.()a-z]+)\.html}
    end
    if host.include?("ecfr") && (sec = path[/section-([\d.]+)/, 1])
      return "#{path[/title-(\d+)/, 1] || 37} CFR § #{sec}"
    end
    if (host.include?("cornell") || host.include?("uscode")) && (sec = path[%r{/35/(\w+)}, 1] || path[/section(\w+)/, 1])
      return "35 U.S.C. § #{sec}"
    end
    if host.include?("epo.org") && (g = path[/guidelines-epc\/\d+\/([a-z]+_[ivx]+(?:_\d+)*)/i, 1])
      part, chap, *rest = g.split("_")
      return "EPO Guidelines #{part.upcase}-#{chap.upcase}, #{rest.join('.')}".delete_suffix(", ")
    end
    tail = path.split("/").reject(&:blank?).last.to_s.sub(/\.\w+\z/, "").tr("-_", "  ").squish
    tail.present? ? tail.humanize.truncate(56) : host
  end
end
