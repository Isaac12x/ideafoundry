namespace :email_ingestion do
  desc "Verify email ingestion configuration"
  task verify: :environment do
    checks = []

    # 1. Resend API key
    api_key = ENV["RESEND_API_KEY"].presence || Rails.application.credentials.dig(:resend, :api_key)
    if api_key.present?
      checks << ["RESEND_API_KEY", "set (#{api_key.length} chars)", true]
    else
      checks << ["RESEND_API_KEY", "MISSING — set env var or credentials", false]
    end

    # 2. Webhook signing secret
    webhook_secret = ENV["RESEND_WEBHOOK_SECRET"]
    if webhook_secret.present?
      checks << ["RESEND_WEBHOOK_SECRET", "set (#{webhook_secret.length} chars)", true]
    else
      checks << ["RESEND_WEBHOOK_SECRET", "MISSING — set env var from Resend dashboard", false]
    end

    # 3. Mailer from
    from_email = Rails.application.credentials.dig(:mailer, :from_email)
    if from_email.present?
      checks << ["Mailer from_email", from_email, true]
    else
      checks << ["Mailer from_email", "MISSING — using fallback from@example.com", false]
    end

    # 4. Mailbox routing
    routing = ApplicationMailbox.router.routes
    if routing.any?
      checks << ["Mailbox routing", "#{routing.size} route(s) configured", true]
    else
      checks << ["Mailbox routing", "NO ROUTES — check app/mailboxes/application_mailbox.rb", false]
    end

    # 5. IdeasMailbox exists
    begin
      IdeasMailbox
      checks << ["IdeasMailbox", "loaded", true]
    rescue NameError
      checks << ["IdeasMailbox", "MISSING", false]
    end

    # 6. SHA3 key
    sha3_key = Rails.application.credentials.dig(:email_ingestion, :sha3_key)
    if sha3_key.present?
      checks << ["SHA3 signing key", "set (#{sha3_key.length} chars)", true]
    else
      checks << ["SHA3 signing key", "MISSING — run `rails credentials:edit`", false]
    end

    # Print results
    puts "\nEmail Ingestion Configuration (Resend Webhook)"
    puts "=" * 50
    checks.each do |label, value, ok|
      status = ok ? "OK" : "FAIL"
      puts "  [#{status.ljust(4)}] #{label}: #{value}"
    end

    failed = checks.count { |_, _, ok| !ok }
    puts "\n#{checks.size - failed}/#{checks.size} checks passed"
    exit(1) if failed > 0
  end
end
