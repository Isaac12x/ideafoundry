require "cgi"
require "openssl"
require "rqrcode"
require "securerandom"

class AuthenticatorApp
  ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".freeze
  DIGITS = 6
  ISSUER = "Idea Foundry".freeze
  PERIOD = 30

  class << self
    def generate_secret(byte_length: 20)
      base32_encode(SecureRandom.random_bytes(byte_length))
    end

    def code(secret, at: Time.current)
      hotp(secret, at.to_i / PERIOD)
    end

    def verify_code(secret, submitted_code, at: Time.current, drift: 1)
      normalized_code = submitted_code.to_s.gsub(/\D/, "")
      return false unless normalized_code.match?(/\A\d{#{DIGITS}}\z/)

      current_counter = at.to_i / PERIOD
      (-drift..drift).any? do |offset|
        counter = current_counter + offset
        next false if counter.negative?

        expected_code = hotp(secret, counter)
        ActiveSupport::SecurityUtils.secure_compare(expected_code, normalized_code)
      end
    rescue ArgumentError
      false
    end

    def provisioning_uri(secret:, account:, issuer: ISSUER)
      label = "#{url_encode(issuer)}:#{url_encode(account)}"
      query = {
        "secret" => secret,
        "issuer" => issuer,
        "algorithm" => "SHA1",
        "digits" => DIGITS,
        "period" => PERIOD
      }.map { |key, value| "#{url_encode(key)}=#{url_encode(value)}" }.join("&")

      "otpauth://totp/#{label}?#{query}"
    end

    def qr_svg(uri)
      RQRCode::QRCode.new(uri).as_svg(
        color: "000",
        module_size: 5,
        shape_rendering: "crispEdges",
        standalone: true,
        use_path: true,
        viewbox: true
      )
    end

    private

    def hotp(secret, counter)
      key = base32_decode(secret)
      hmac = OpenSSL::HMAC.digest("SHA1", key, [counter].pack("Q>"))
      offset = hmac.bytes.last & 0x0f
      truncated_hash = hmac.byteslice(offset, 4).unpack1("N") & 0x7fffffff

      (truncated_hash % (10**DIGITS)).to_s.rjust(DIGITS, "0")
    end

    def base32_encode(bytes)
      bits = bytes.bytes.map { |byte| byte.to_s(2).rjust(8, "0") }.join
      bits += "0" * ((5 - bits.length % 5) % 5)
      bits.scan(/.{5}/).map { |chunk| ALPHABET[chunk.to_i(2)] }.join
    end

    def base32_decode(value)
      normalized = value.to_s.upcase.delete("= \n\t-")
      raise ArgumentError, "invalid base32 secret" unless normalized.match?(/\A[A-Z2-7]+\z/)

      bits = normalized.chars.map { |char| ALPHABET.index(char).to_s(2).rjust(5, "0") }.join
      bits.scan(/.{8}/).map { |chunk| chunk.to_i(2).chr }.join
    end

    def url_encode(value)
      CGI.escape(value.to_s).gsub("+", "%20")
    end
  end
end
