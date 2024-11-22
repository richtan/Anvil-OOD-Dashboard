module Api
    class JobsDataController < ApplicationController
        def getuserdata
            output = `sacct -S now-100000days -P -n -u #{@user} -o #{MyJobsController::SACCT_FIELDS.join(",")}`
      
            if $?.success?
              interactive_app_regex = %r{\A/home/#{Regexp.escape(@user.to_s)}/ondemand/data/sys/dashboard/batch_connect/sys/\w+/output/(?<uuid>[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12})\z}
              jobs = {}
      
              output.each_line do |line|
                s = line.strip.split("|")
                job_id = s[0].split(".")[0]
      
                if !jobs.has_key?(job_id)
                  jobs[job_id] = MyJobsController::FIELDS.keys.map { |field| [field, ""] }.to_h.merge(MyJobsController::SACCT_FIELDS.zip(s).to_h)
                  match_interactive_app = jobs[job_id]["workdir"].match(interactive_app_regex)
                  jobs[job_id]["sessionid"] = match_interactive_app ? match_interactive_app["uuid"] : "N/A"
                else
                  MyJobsController::PREFER_MAX_FIELDS.each do |field|
                    jobs[job_id][field] = [jobs[job_id][field], s[MyJobsController::SACCT_FIELDS.index(field)]].max_by { |val| MyJobsController::FIELDS[field]["compare_fn"].call(val) }
                  end
                end
              end
      
              jobs_hash = jobs.values.map do |j|
                [MyJobsController::SIZE_FIELDS, MyJobsController::DURATION_FIELDS, MyJobsController::TIMESTAMP_FIELDS].flatten.each do |field|
                  j[field] = MyJobsController::FIELDS[field]["compare_fn"].call(j[field])
                end
      
                j["timeeff"] = (j["elapsed"].to_f * 100 / j["timelimit"].to_f).round(2)
                j["cpueff"] = (j["totalcpu"].to_f * 100 / (j["alloccpus"].to_f * j["elapsed"].to_f)).round(2)
                j["memeff"] = (j["maxrss"].to_f * 100 / j["reqmem"].to_f).round(2)
      
                j
              end
      
              render json: jobs_hash, status: :ok
            else
              head :internal_server_error
            end
          end
        
        def getsacctuser
            output = `sacct -u #{@user} -S now-100000days -X -o JobID,Submit,Start,End,`

            lines = output.split("\n")
            headers = lines[0].split.map(&:strip)
            
            data = lines[2..-1].map do |line|
                values = line.split.map(&:strip)
                headers.zip(values).to_h
            end

            render json: data
        end
    end
end