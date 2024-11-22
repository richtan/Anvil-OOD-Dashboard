module Api
  class DiskUsageController < ApplicationController
    def get
      result = Util.get_myquota(@user)

      if result
        render json: result.split("\n").drop(3).map { |line|
          s = line.split
          { type: s[0], location: s[1], disk_usage: s[2], disk_usage_limit: s[3], disk_usage_percentage: s[4], file_count: s[5], file_count_limit: s[6], file_count_percentage: s[7] }
        }.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
