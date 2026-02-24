class CoolOffTransitionJob < ApplicationJob
  queue_as :default

  def perform(idea)
    # Check if cool-off period has expired and idea still exists
    return unless idea.persisted? && idea.cool_off_expired?
    
    # Transition idea back to editable state
    idea.reopen_from_cool_off!
  end
end