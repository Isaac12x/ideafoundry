require "net/http"
require "json"

module Kb
  # Finds the Wikipedia and Grokipedia article for a Problem and writes each as Markdown + .source.json sidecar
  # beside problem.md, then links them from problem.md. Each site fails independently (best effort).
  module ProblemResearch
    UA = "idea-app/1.0 (personal knowledge base)".freeze
    MARK = "## Research".freeze

    module_function

    # => [{ site:, title:, file: }, ...] for the sites that matched
    def run!(problem)
      FileUtils.mkdir_p(problem.abs_dir)
      seed(problem)
      found = [ wikipedia(problem.title), grokipedia(problem.title) ].filter_map do |art|
        next unless art
        file = "#{art[:site]} - #{art[:title].gsub(%r{[/\\:]}, "-")}.md"
        abs = File.join(problem.abs_dir, file)
        File.write(abs, art[:markdown])
        Kb::Source.write!(abs, url: art[:url], description: art[:description])
        art.merge(file: file)
      end
      link!(problem, found)
      found
    end

    def seed(problem)
      path = File.join(problem.abs_dir, "problem.md")
      File.write(path, "# #{problem.title}\n\n## Need\n\n#{problem.need}\n") unless File.exist?(path)
    end

    def link!(problem, found)
      path = File.join(problem.abs_dir, "problem.md")
      text = File.read(path)
      lines = found.filter_map { |f| "- [#{f[:site]}: #{f[:title]}](#{ERB::Util.url_encode(f[:file])})" unless text.include?("](#{ERB::Util.url_encode(f[:file])})") }
      return if lines.empty?
      text = "#{text.rstrip}\n\n#{MARK}\n" unless text.include?(MARK)
      File.write(path, "#{text.rstrip}\n#{lines.join("\n")}\n")
    end

    def wikipedia(query)
      hit = json("https://en.wikipedia.org/w/api.php", action: "query", list: "search", srsearch: query, srlimit: 1, format: "json")
        .dig("query", "search", 0) or return
      title = hit["title"]
      page = json("https://en.wikipedia.org/w/api.php", action: "query", prop: "extracts|info", explaintext: 1, titles: title,
                  inprop: "url", redirects: 1, format: "json").dig("query", "pages")&.values&.first or return
      text = page["extract"].to_s.gsub(/^====\s*(.+?)\s*====$/, "#### \\1").gsub(/^===\s*(.+?)\s*===$/, "### \\1")
                            .gsub(/^==\s*(.+?)\s*==$/, "## \\1")
      return if text.blank?
      { site: "Wikipedia", title: title, url: page["fullurl"] || "https://en.wikipedia.org/wiki/#{ERB::Util.url_encode(title.tr(' ', '_'))}",
        description: text.split("\n").first.to_s, markdown: "# #{title}\n\n#{text}\n" }
    rescue StandardError => e
      Rails.logger.info("Wikipedia lookup failed: #{e.message}")
      nil
    end

    # Grokipedia has no documented API: uses its public typeahead + page HTML; any change just yields nil.
    def grokipedia(query)
      hit = json("https://grokipedia.com/api/typeahead", query: query, limit: 1)["results"]&.first or return
      url = "https://grokipedia.com/page/#{ERB::Util.url_encode(hit["slug"])}"
      article = Nokogiri::HTML(get(url)).at_css("article") or return
      body = article.css("h1,h2,h3,h4,p,li").filter_map do |n|
        t = n.text.squish
        next if t.blank?
        n.name =~ /\Ah(\d)\z/ ? "#{'#' * $1.to_i} #{t}" : (n.name == "li" ? "- #{t}" : t)
      end.join("\n\n")
      return if body.length < 200
      { site: "Grokipedia", title: hit["title"], url: url, description: hit["snippet"], markdown: body + "\n" }
    rescue StandardError => e
      Rails.logger.info("Grokipedia lookup failed: #{e.message}")
      nil
    end

    def json(url, params) = JSON.parse(get("#{url}?#{params.to_query}"))

    # Seam for tests (stubbed; no network in the suite).
    def get(url)
      res = Net::HTTP.start(URI(url).host, 443, use_ssl: true, open_timeout: 10, read_timeout: 30) do |http|
        http.get(URI(url).request_uri, "User-Agent" => UA, "Accept-Language" => "en")
      end
      res.is_a?(Net::HTTPSuccess) ? res.body : raise("HTTP #{res.code}")
    end
  end
end
