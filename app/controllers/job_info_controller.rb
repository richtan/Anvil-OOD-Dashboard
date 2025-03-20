require "json"

class JobInfoController < ApplicationController
  def json
    jobid = params[:jobid]

    # Make sure job id is valid
    if !(/^\d+(_\d+)?$/.match?(jobid))
      head :internal_server_error
    end

    # Cache jobinfo results for jobs that have an exit code
    # because their info won't change anymore, unlike
    # running or pending jobs, which may change wall time,
    # CPU usage, etc. over time
    cache_key = "job_info/#{jobid}"
    cached_result = Rails.cache.read(cache_key)

    if cached_result.present? && cached_result["ExitCode"] != "--"
      result_hash = cached_result
    else
      # Credit to @birc-aeh (https://github.com/birc-aeh/slurm-utils) for jobinfo helper script
      result = `jobinfo -v #{jobid}`
      if $?.success?
        result_hash = result.split("\n").map { |line|
          s = line.split(":", 2).map(&:strip)
          s
        }.to_h
        Rails.cache.write(cache_key, result_hash)
      else
        result_hash = nil
      end
    end

    if result_hash
      render json: result_hash.to_json, status: :ok
    else
      head :internal_server_error
    end
  end
end
