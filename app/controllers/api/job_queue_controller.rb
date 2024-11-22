module Api
  class JobQueueController < ApplicationController
    def get
      result = Util.get_squeue() || []

      if result
        render json: result.select { |job| job[:user] == @user.to_s }.sort_by { |job| job[:jobid] }.reverse.first(5).to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
