class ProfilesController < ApplicationController
  before_action :require_login

  # The profile form grows often; accept whatever fields it sends.
  def update
    current_user.update!(params.require(:user).permit!)
    redirect_to profile_path
  end
end
