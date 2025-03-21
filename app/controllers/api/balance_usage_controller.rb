module Api
  class BalanceUsageController < ApplicationController
    def get
      result = Util.get_mybalance(@user)

      if result
        render json: result.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
