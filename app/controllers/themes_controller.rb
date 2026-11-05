# Themes group ideas (e.g. "Productizing"). Created via IdeasController (new_theme_names); managed in Settings.
class ThemesController < ApplicationController
  before_action :set_user
  before_action :set_theme

  def update
    if @theme.update(params.require(:theme).permit(:name, :color))
      redirect_back fallback_location: ideas_path, notice: "Theme updated."
    else
      redirect_back fallback_location: ideas_path, alert: @theme.errors.full_messages.to_sentence
    end
  end

  def destroy
    @theme.destroy
    redirect_back fallback_location: ideas_path, notice: "Theme deleted."
  end

  private

  def set_theme
    @theme = @user.themes.find(params[:id])
  end
end
