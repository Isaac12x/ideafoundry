require "rack/attack"

Rack::Attack.throttle("recovery_secret/ip", limit: 5, period: 15.minutes) do |req|
  req.ip if req.path == "/recovery_secret" && req.post?
end

Rack::Attack.throttle("upgrades/ip", limit: 3, period: 1.hour) do |req|
  req.ip if req.path == "/upgrade" && req.post?
end

Rack::Attack.throttled_responder = ->(request) {
  period = request.env["rack.attack.match_data"]&.dig(:period) || 900
  [ 429,
    { "Content-Type" => "text/plain", "Retry-After" => period.to_s },
    [ "Too many requests. Try again later." ]
  ]
}
