begin
  Resend.api_key = Rails.application.credentials.dig(:resend, :api_key)
rescue ActiveSupport::MessageEncryptor::InvalidMessage, ArgumentError, Errno::ENOENT, Errno::EISDIR
  Resend.api_key = nil
end

ENV["RESEND_API_KEY"] ||= Resend.api_key
