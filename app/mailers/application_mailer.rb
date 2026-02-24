class ApplicationMailer < ActionMailer::Base
  default from: -> {
    email = Rails.application.credentials.dig(:mailer, :from_email) || "from@example.com"
    name = Rails.application.credentials.dig(:mailer, :from_name)
    name.present? ? "#{name} <#{email}>" : email
  }
  layout "mailer"
end
