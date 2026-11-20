require "net/http"

# Thin client for the local embedding + vector sidecar (infra/services/semantic). Off unless SEMANTIC_SERVICE_URL is set.
# Every failure (network, HTTP, JSON) is logged and returns nil, so callers fall back (palette Similar -> TF-IDF) and nothing raises into a request.
module SemanticSearch
  OPEN_TIMEOUT = 1
  SEARCH_TIMEOUT = 5
  UPSERT_TIMEOUT = 60

  module_function

  def enabled? = ServiceSettings.fetch("SEMANTIC_SERVICE_URL").present?

  def idea_id(user_id, idea_id) = "u#{user_id}:idea:#{idea_id}"
  def kb_id(user_id, src, path) = "u#{user_id}:kb:#{src}:#{path}"
  def prefix(user_id) = "u#{user_id}:"

  # items: [{ id:, text: }]; empty text deletes. -> { "embedded", "skipped" } or nil
  def upsert(items) = post("/upsert", { items: items }, UPSERT_TIMEOUT)
  def delete(ids) = post("/delete", { ids: ids }, SEARCH_TIMEOUT)
  def prune(prefix, keep) = post("/prune", { prefix: prefix, keep: keep }, UPSERT_TIMEOUT)

  # By query text or by a stored doc id. -> [{ "id", "score" }] or nil (disabled/error)
  def search(prefix:, query: nil, id: nil, k: 12, exclude: [])
    post("/search", { query: query, id: id, prefix: prefix, k: k, exclude: exclude }.compact, SEARCH_TIMEOUT)&.fetch("hits", nil)
  end

  def post(path, payload, read_timeout)
    return unless enabled?

    uri = URI.join("#{ServiceSettings.fetch('SEMANTIC_SERVICE_URL').delete_suffix('/')}/", path.delete_prefix("/"))
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: OPEN_TIMEOUT, read_timeout: read_timeout) do |http|
      http.post(uri.path, payload.to_json, "Content-Type" => "application/json")
    end
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
