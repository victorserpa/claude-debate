class ProfilesController < ApplicationController
  before_action :require_login

  def update
    current_user.update!(params.require(:user).permit(:name, :bio))
    redirect_to profile_path
  end
end
