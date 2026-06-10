module SemverCompare
  SECURITY_KEYWORDS = %w[CVE vuln vulnerability exploit security].freeze

  def self.parse(tag)
    tag.gsub(/^v/, '').split('.').map(&:to_i)
  end

  def self.distance(current, latest)
    c = parse(current)
    l = parse(latest)
    { major: l[0] - c[0], minor: l[1] - c[1], patch: l[2] - c[2] }
  end

  def self.severity(current, latest, release_body)
    return "red" if security_release?(release_body)
    d = distance(current, latest)
    return "yellow" if d[:major] > 0 || d[:minor] >= 4 || d[:patch] >= 10
    "green"
  end

  def self.security_release?(body)
    return false if body.blank?
    SECURITY_KEYWORDS.any? { |kw| body.match?(/#{kw}/i) }
  end
end
