require "json"
require "rqrcode"

class MobileUplink
  DEFAULT_INSTALL_URL = "https://ideas.local:8443/mobile-uplink/install".freeze
  ENCRYPTION_LAYERS = [
    "device-local sealed storage",
    "workspace recipient envelope",
    "AES-256-GCM payload encryption",
    "ChaCha20-Poly1305 transport wrap"
  ].freeze

  class << self
    def install_url
      ENV.fetch("MOBILE_UPLINK_INSTALL_URL", DEFAULT_INSTALL_URL)
    end

    def pairing_payload(uplink_id:, workspace_url:)
      {
        "type" => "idea-foundry.mobile-uplink.pairing",
        "version" => 1,
        "uplink_id" => uplink_id.to_s,
        "workspace_url" => workspace_url.to_s,
        "encryption" => {
          "mode" => "super-secure",
          "layers" => ENCRYPTION_LAYERS,
          "decoded_by" => "this user's Idea Foundry instance only"
        }
      }.to_json
    end

    def qr_svg(value)
      RQRCode::QRCode.new(value).as_svg(
        color: "000",
        module_size: 5,
        shape_rendering: "crispEdges",
        standalone: true,
        use_path: true,
        viewbox: true
      )
    end
  end
end
