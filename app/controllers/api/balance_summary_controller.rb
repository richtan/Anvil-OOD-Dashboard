module Api
  class BalanceSummaryController < ApplicationController
    def get
      allocation = params[:allocation]
      result = Util.get_balance_summary(@user, allocation)

      if result
        if result == :not_in_allocation
          head :forbidden
        else
          render json: result.to_json, status: :ok
        end
      else
        head :internal_server_error
      end
    end
  end
end
