require "net/http"

# Thin client for the local embedding + vector sidecar (infra/services/semantic). Off unless SEMANTIC_SERVICE_URL is set.
# Every failure (network, HTTP, JSON) is logged and returns nil, so callers fall back (palette Similar -> TF-IDF) and nothing raises into a request.
module SemanticSearch
  OPEN_TIMEOUT = 1
  SEARCH_TIMEOUT = 5
  UPSERT_TIMEOUT = 60

  module_function

  def enabled? = ServiceSettings.fetch("SEMANTIC_SERVICE_URL").present?

  def idea_id(user_id, idea_id) = record_id(user_id, "idea", idea_id)
  def record_id(user_id, type, key) = "u#{user_id}:#{type}:#{key}"
  def kb_id(user_id, src, path) = "u#{user_id}:kb:#{src}:#{path}"
  def prefix(user_id) = "u#{user_id}:"

  # items: [{ id:, sections: [str] }]; empty sections deletes. Queued by the sidecar (latest per id wins), only changed sections are re-embedded.
  # -> { "queued" } or nil
  def enqueue(items) = post("/enqueue", { items: items }, UPSERT_TIMEOUT)
  def delete(ids) = post("/delete", { ids: ids }, SEARCH_TIMEOUT)
  def prune(prefix, keep) = post("/prune", { prefix: prefix, keep: keep }, UPSERT_TIMEOUT)
  def rebuild! = post("/rebuild", {}, SEARCH_TIMEOUT)
  def rebuild_commit! = post("/rebuild/commit", {}, UPSERT_TIMEOUT)
  def rebuild_abort! = post("/rebuild/abort", {}, SEARCH_TIMEOUT)
  def health = get("/health")

  # By query text or by a stored doc id; types limits to id types (e.g. %w[idea note]). -> [{ "id", "score" }] or nil (disabled/error)
  def search(prefix:, query: nil, id: nil, k: 12, exclude: [], types: nil)
    post("/search", { query: query, id: id, prefix: prefix, k: k, exclude: exclude, types: types }.compact, SEARCH_TIMEOUT)&.fetch("hits", nil)
  end

  def get(path) = request(path) { |http, uri| http.get(uri.path) }

  def post(path, payload, read_timeout)
    request(path, read_timeout) { |http, uri| http.post(uri.path, payload.to_json, "Content-Type" => "application/json") }
  end

  def request(path, read_timeout = SEARCH_TIMEOUT)
    return unless enabled?

    uri = URI.join("#{ServiceSettings.fetch('SEMANTIC_SERVICE_URL').delete_suffix('/')}/", path.delete_prefix("/"))
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: read_timeout) { |http| yield http, uri }
    unless res.is_a?(Net::HTTPSuccess)
      Rails.logger.warn("SemanticSearch #{path}: HTTP #{res.code}")
      return
    end
    JSON.parse(res.body)
  rescue StandardError => e
    Rails.logger.warn("SemanticSearch #{path}: #{e.class}: #{e.message}")
    nil
  end
end
