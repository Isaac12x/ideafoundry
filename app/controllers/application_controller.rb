class ApplicationController < ActionController::Base
  private

  def set_user
    @user = User.first || User.create!(email: 'user@example.com', name: 'Default User')
  end
end
