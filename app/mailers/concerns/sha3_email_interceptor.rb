# frozen_string_literal: true

class Sha3EmailInterceptor
  def self.delivering_email(message)
    body = message.body.to_s
    digest = SHA3::Digest::SHA256.hexdigest(body)
    message.header['X-Content-SHA3'] = digest
  end
end
