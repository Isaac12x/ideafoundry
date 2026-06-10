require "json"
require "net/http"
require "securerandom"
require "uri"

class NoteOauthImportService
  PROVIDERS = {
    "notion" => {
      authorize_url: "https://api.notion.com/v1/oauth/authorize",
      token_url: "https://api.notion.com/v1/oauth/token",
      client_id_env: "NOTION_CLIENT_ID",
      client_secret_env: "NOTION_CLIENT_SECRET"
    }
  }.freeze

  def initialize(source:, session:, callback_url:)
    @source = NoteImportService.normalize_source!(source)
    @session = session
    @callback_url = callback_url
  end

  def authorization_uri
    provider = provider_config
    state = SecureRandom.hex(24)
    session[state_key] = state

    uri = URI(provider.fetch(:authorize_url))
    uri.query = URI.encode_www_form(
      client_id: credential!(provider.fetch(:client_id_env)),
      response_type: "code",
      owner: "user",
      redirect_uri: callback_url,
      state: state
    )
    uri
  end

  def preview_from_callback(params)
    provider = provider_config
    verify_state!(params[:state])
    code = params[:code].presence || raise(NoteImportService::ImportError, "#{source_label} did not return an authorization code.")

    token = exchange_code(provider, code)
    notes = fetch_notes(token)
    NoteImportService.preview_from_notes(source: source, notes: notes)
  end

  private

  attr_reader :source, :session, :callback_url

  def provider_config
    PROVIDERS[source] || raise(
      NoteImportService::ImportError,
      "#{source_label} does not expose a supported OAuth import API here yet. Use an export file for now."
    )
  end

  def exchange_code(provider, code)
    uri = URI(provider.fetch(:token_url))
    request = Net::HTTP::Post.new(uri)
    request.basic_auth credential!(provider.fetch(:client_id_env)), credential!(provider.fetch(:client_secret_env))
    request["Content-Type"] = "application/json"
    request.body = {
      grant_type: "authorization_code",
      code: code,
      redirect_uri: callback_url
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") { |http| http.request(request) }
    body = JSON.parse(response.body)
    return body.fetch("access_token") if response.is_a?(Net::HTTPSuccess) && body["access_token"].present?

    raise NoteImportService::ImportError, "#{source_label} OAuth failed: #{body["error_description"].presence || body["error"].presence || response.message}"
  rescue JSON::ParserError
    raise NoteImportService::ImportError, "#{source_label} OAuth returned an unreadable response."
  end

  def fetch_notes(token)
    case source
    when "notion"
      fetch_notion_pages(token)
    else
      []
    end
  end

  def fetch_notion_pages(token)
    uri = URI("https://api.notion.com/v1/search")
    request = Net::HTTP::Post.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Content-Type"] = "application/json"
    request["Notion-Version"] = "2022-06-28"
    request.body = {
      filter: { property: "object", value: "page" },
      page_size: 100
    }.to_json

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    body = JSON.parse(response.body)
    raise NoteImportService::ImportError, "Notion import failed: #{body["message"].presence || response.message}" unless response.is_a?(Net::HTTPSuccess)

    Array(body["results"]).filter_map do |page|
      title = notion_title(page).presence || "Untitled Notion page"
      body = fetch_notion_block_text(token, page["id"]).presence || title

      NoteImportService.build_import_note(
        title: title,
        body: body,
        folders: ["Notion"],
        source_path: "Notion/#{page["id"]}",
        metadata: {
          "notion_id" => page["id"],
          "url" => page["url"],
          "last_edited_time" => page["last_edited_time"]
        }.compact
      )
    end
  rescue JSON::ParserError
    raise NoteImportService::ImportError, "Notion returned an unreadable response."
  end

  def fetch_notion_block_text(token, block_id)
    uri = URI("https://api.notion.com/v1/blocks/#{block_id}/children?page_size=100")
    request = Net::HTTP::Get.new(uri)
    request["Authorization"] = "Bearer #{token}"
    request["Notion-Version"] = "2022-06-28"

    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(request) }
    body = JSON.parse(response.body)
    return "" unless response.is_a?(Net::HTTPSuccess)

    Array(body["results"]).filter_map { |block| notion_block_text(block) }.join("\n").strip
  rescue JSON::ParserError
    ""
  end

  def notion_block_text(block)
    value = block[block["type"]].to_h
    text = Array(value["rich_text"]).map { |part| part["plain_text"] }.join
    return text if text.present?

    value["caption"].presence || value["url"].presence
  end

  def notion_title(page)
    properties = page["properties"].to_h
    title_property = properties.values.find { |property| property["type"] == "title" }
    Array(title_property&.dig("title")).map { |part| part.dig("plain_text") }.join
  end

  def verify_state!(state)
    expected = session.delete(state_key)
    return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(expected, state.to_s)

    raise NoteImportService::ImportError, "#{source_label} OAuth state could not be verified."
  end

  def credential!(env_key)
    ENV[env_key].presence || raise(NoteImportService::ImportError, "#{source_label} OAuth is not configured. Set #{env_key}.")
  end

  def state_key
    "note_import_oauth_state_#{source}"
  end

  def source_label
    NoteImportService.source_label_for(source)
  end
end
