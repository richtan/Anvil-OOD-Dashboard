require "uri"
require "net/http"
require "json"

module Api
  class NewsFeedController < ApplicationController
    # 1: Outages and Maintenance
    # 2: Announcements
    # 6: Outages
    # 7: Maintenance
    NEWS_TYPE_IDS = [1, 2, 6, 7]

    def get
      result = CustomCache.fetch("news_feed", expires_in: 3.hours, race_condition_ttl: 3.seconds) do
        uri = URI("https://www.rcac.purdue.edu/api/news?resource=99&limit=30")
        res = Net::HTTP.get_response(uri)

        if res.is_a?(Net::HTTPSuccess)
          json_data = JSON.parse(res.body)
          articles = json_data["data"]
          filtered = articles.select { |article| NEWS_TYPE_IDS.include?(article["newstypeid"].to_i) }
          parsed = filtered.map { |article|
            {
              uri: article["uri"],
              headline: article["headline"],
              formattedbody: article["formattedbody"],
              formatteddate: article["formatteddate"],
              formattedcreateddate: article["formattedcreateddate"],
              datetimeedited: article["datetimeedited"],
            }
          }
          parsed
        else
          return false
        end
      end

      if result
        render json: result.to_json, status: :ok
      else
        head :internal_server_error
      end
    end
  end
end
