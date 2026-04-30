class IdeaDigestJob < ApplicationJob
  queue_as :default

  # Accepts period as a positional or keyword arg for flexibility with recurring scheduler.
  def perform(period_or_opts = "daily", period: nil)
    period ||= if period_or_opts.is_a?(Hash)
                 period_or_opts[:period] || period_or_opts["period"]
               else
                 period_or_opts
               end
    period ||= "daily"
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
