# Clip start/end for video downloads: parsing ("354", "5m54s", "1:02:03"),
# lifting them out of a URL (t=/start=/end=, #t=start,end) and yt-dlp output.
module Kb
  module ClipTime
    HMS = /\A(?:(\d+)h)?(?:(\d+)m)?(?:(\d+(?:\.\d+)?)s?)?\z/i

    # Seconds (Integer) or nil.
    def self.parse(value)
      s = value.to_s.strip.delete_prefix("npt:")
      return if s.empty?

      if s.include?(":")
        parts = s.split(":", -1)
        return unless parts.size.between?(2, 3) && parts.all? { |p| p.match?(/\A\d+(?:\.\d+)?\z/) }
        parts.map(&:to_f).inject(0) { |acc, n| acc * 60 + n }.floor
      elsif (m = s.match(HMS)) && m[1..3].any?
        (m[1].to_i * 3600 + m[2].to_i * 60 + m[3].to_f).floor
      end
    end

    # => [start, end], either nil. Explicit #t=start,end wins over ?t=/&end=.
    def self.from_url(url)
      url = url.to_s
      frag = url[/#.*/].to_s
      query = url.sub(/#.*/, "")
      if (m = frag.match(/[#&]t=([^&]*)/))
        from, to = m[1].split(",", 2)
        return [ parse(from), parse(to) ]
      end
      [ parse(param(query, "t") || param(query, "start") || param(frag, "start")), parse(param(query, "end") || param(frag, "end")) ]
    end

    def self.param(str, name) = str[/[?&]#{name}=([^&#]*)/, 1]

    # 354 -> "5:54", 3723 -> "1:02:03"
    def self.format(sec)
      h, rem = sec.divmod(3600)
      m, s = rem.divmod(60)
      h.positive? ? Kernel.format("%d:%02d:%02d", h, m, s) : Kernel.format("%d:%02d", m, s)
    end

    # 354 -> "5m54s" (filename-safe)
    def self.slug(sec)
      h, rem = sec.divmod(3600)
      m, s = rem.divmod(60)
      "#{"#{h}h" if h.positive?}#{"#{m}m" if h.positive? || m.positive?}#{s}s"
    end

    # yt-dlp --download-sections value.
    def self.section(from, to) = "*#{from || 0}-#{to || "inf"}"
  end
end
