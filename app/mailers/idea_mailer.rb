class IdeaMailer < ApplicationMailer
  def share_idea(idea, recipient_email, sender_name: nil, event_type: nil, metadata: {})
    @idea = idea
    @user = idea.user
    @theme = event_type ? EmailPresetHelper.preset_for(event_type, @user) : EmailPresetHelper::PRESETS['neutral']
    @sender_name = sender_name || @user.name
    @event_type = event_type
    @metadata = metadata
    @content_prefs = event_type ? @user.notification_content(event_type) : {}

    subject = event_type ? event_subject(event_type, idea) : "Idea: #{@idea.title}"

    mail(
      to: recipient_email,
      subject: subject
    )
  end

  def share_list(list, recipient_email, sender_name: nil)
    @list = list
    @ideas = list.ideas.includes(:topologies).order("idea_lists.position")
    @user = list.user
    @theme = EmailPresetHelper::PRESETS['neutral']
    @sender_name = sender_name || @user.name

    mail(
      to: recipient_email,
      subject: "List: #{@list.name} (#{@ideas.size} ideas)"
    )
  end

  def event_notification(idea, recipient_email, event_type:, metadata: {})
    @idea = idea
    @user = idea.user
    @theme = EmailPresetHelper.preset_for(event_type, @user)
    @event_type = event_type
    @metadata = metadata
    @content_prefs = @user.notification_content(event_type)

    mail(
      to: recipient_email,
      subject: event_subject(event_type, idea)
    )
  end

  def digest(user, recipient_email, ideas:, period:)
    @user = user
    @ideas = ideas
    @period = period
    @theme = EmailPresetHelper.preset_for("digest_#{period}", user)
    @content_prefs = user.notification_content("digest_#{period}")

    mail(
      to: recipient_email,
      subject: "Your #{period} idea digest — #{ideas.size} idea#{'s' if ideas.size != 1} updated"
    )
  end

  private

  def event_subject(event_type, idea)
    case event_type.to_s
    when "state_changed"  then "Idea state changed: #{idea.title}"
    when "score_changed"  then "Score updated: #{idea.title}"
    when "added_to_list"  then "Idea added to list: #{idea.title}"
    when "created"        then "New idea created: #{idea.title}"
    when "webhook_triggered" then "Webhook update: #{idea.title}"
    else "Notification: #{idea.title}"
    end
  end
end
