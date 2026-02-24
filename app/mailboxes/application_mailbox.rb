class ApplicationMailbox < ActionMailbox::Base
  # Route all emails to ideas mailbox
  routing :all => :ideas
end
