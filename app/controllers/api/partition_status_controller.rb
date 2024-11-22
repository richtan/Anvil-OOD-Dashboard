module Api
  class PartitionStatusController < ApplicationController
    def get
      result = Util.get_partition_statuses()

      if result
        render json: result.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
