class IdeaDigestJob < ApplicationJob
  queue_as :default

  def perform(period:)
    trigger = "digest_#{period}"

    User.find_each do |user|
      next unless user.notification_enabled?(trigger)

      recipients = user.email_recipients
      next if recipients.empty?

      since = case period.to_s
              when "daily" then 1.day.ago
              when "weekly" then 1.week.ago
              else 1.day.ago
              end

      ideas = user.ideas.where("updated_at >= ?", since).order(updated_at: :desc)
      next if ideas.empty?

      recipients.each do |recipient|
        IdeaMailer.digest(user, recipient, ideas: ideas, period: period).deliver_later
      end
    end
  end
end
