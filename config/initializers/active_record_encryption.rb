# Active Record encryption keys derived from secret_key_base (no separate
# credentials entry needed). Used by ApiKey#token so keys can be revealed.
# ponytail: rotating secret_key_base makes stored tokens unreadable; digest auth is unaffected.
generator = ->(purpose) { Rails.application.key_generator.generate_key("active_record_encryption/#{purpose}", 32) }
# Credentials (active_record_encryption.*) win over derived keys: the railtie applies
# credentials over config, so only derive when they are absent.
creds = Rails.application.credentials.active_record_encryption || {}
Rails.application.config.active_record.encryption.tap do |enc|
  enc.primary_key = creds[:primary_key] || generator.call("primary").unpack1("H*")
  enc.deterministic_key = creds[:deterministic_key] || generator.call("deterministic").unpack1("H*")
  enc.key_derivation_salt = creds[:key_derivation_salt] || generator.call("salt").unpack1("H*")
end
