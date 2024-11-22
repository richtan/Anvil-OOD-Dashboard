require "open3"

module Util
  def self.to_bytes(value)
    return 0 if value.nil? || value.empty?

    case value[-1]
    when "K"
      value.to_f * 1024
    when "M"
      value.to_f * 1024 * 1024
    when "G"
      value.to_f * 1024 * 1024 * 1024
    when "T"
      value.to_f * 1024 * 1024 * 1024 * 1024
    when "P"
      value.to_f * 1024 * 1024 * 1024 * 1024 * 1024
    else
      value.to_f
    end
  end

  def self.timestr_to_seconds(timestr)
    d_hhmmss_regex = /\A\d+-\d{2}:\d{2}:\d{2}\z/
    hhmmss_regex = /\A\d{2}:\d{2}:\d{2}\z/
    mmss_ms_regex = /\A\d{2}:\d{2}\.\d{3}\z/

    if d_hhmmss_regex.match?(timestr)
      parts = timestr.split("-")
      days = parts.first.to_i
      hours, minutes, seconds = parts.last.split(":").map(&:to_i)
      total_seconds = days * 86400 + hours * 3600 + minutes * 60 + seconds
    elsif hhmmss_regex.match?(timestr)
      hours, minutes, seconds = timestr.split(":").map(&:to_i)
      total_seconds = hours * 3600 + minutes * 60 + seconds
    elsif mmss_ms_regex.match?(timestr)
      minutes, seconds_milliseconds = timestr.split(":")
      seconds, milliseconds = seconds_milliseconds.split(".")
      total_seconds = ((minutes.to_i * 60) + seconds.to_i + (milliseconds.to_i / 1000.0)).round
    else
      return -1
    end

    return total_seconds
  end

  def self.timestamp_to_epoch(timestamp)
    begin
      # Read timestamps in local timezone
      return Time.strptime(timestamp, "%FT%T").to_i
    rescue ArgumentError => e
      return "N/A"
    end
  end

  def self.expand_nodelist(nodelist)
    if nodelist == "None assigned"
      return "N/A"
    end

    expanded_nodes = []

    # Regular expression to match node names with optional ranges
    regex = /(\w+)(?:\[(.*?)\])?/

    # Scan nodelist for matches
    nodelist.scan(regex) do |node_name, range|
      if range.nil?
        # Single node without range
        expanded_nodes << node_name
      else
        # Node with range
        parts = range.split(",")
        parts.each do |part|
          if part.include?("-")
            # Expand range
            start, finish = part.split("-").map(&:to_i)
            (start..finish).each do |num|
              expanded_nodes << "#{node_name}#{num}"
            end
          else
            # Single number in range
            expanded_nodes << "#{node_name}#{part.to_i}"
          end
        end
      end
    end

    # Join nodes with comma
    return expanded_nodes.join(",")
  end

  def self.get_user()
    return `whoami`.split("\n")[0]
  end

  # Based on jobsu script
  def self.get_su_usage(partition, used_seconds, timelimit, reqtres)
    charge_factor = partition == "highmem" ? 4 : 1
    used_hours = used_seconds / 3600.to_f
    reserved_hours = timelimit / 3600.to_f
    reserved_cpus = partition == "wholenode" ? reqtres["node"] * 128 : reqtres["cpu"]
    reserved_gpus = reqtres["gres/gpu"]

    if ["gpu", "gpu-debug"].include?(partition)
      total_used_sus = reserved_gpus * used_hours * charge_factor
      total_sus = reserved_gpus * reserved_hours * charge_factor
    else
      total_used_sus = reserved_cpus * used_hours * charge_factor
      total_sus = reserved_cpus * reserved_hours * charge_factor
    end

    return [total_used_sus, total_sus]
  end

  def self.scontrol_to_hash(output)
    return output.split("\n").map { |line| line.scan(/(?:(?<=\A|\s))([^\s=]+)=((?:(?!\s(?:\S+)=).)*)/).to_h.each_value(&:strip) }.delete_if(&:empty?)
  end

  def self.get_user_allocations(user)
    allocations = CustomCache.fetch("allocations/#{user}", expires_in: 1.days) do
      output = `sacctmgr show user #{user} withassoc format=account -P -n -r | xargs | tr ' ' ',' | tr -d '\n'`

      if $?.success?
        output
      else
        return false
      end
    end

    return allocations
  end

  def self.get_qos_list()
    qos_list = CustomCache.fetch("qos_list", expires_in: 1.days) do
      output = `scontrol show partitions -o`

      if $?.success?
        scontrol_to_hash(output).map { |line_h|
          line_h["QoS"]
        }.uniq
      else
        return false
      end
    end

    return qos_list
  end

  def self.get_mybalance(user)
    allocations = get_user_allocations(user)
    mybalance = CustomCache.fetch("balance_usage/#{user}", expires_in: 2.hours) do
      output = `scontrol show assoc users=#{user} accounts=#{allocations} flags=assoc -o`

      if $?.success?
        scontrol_to_hash(output).select { |line_h| line_h["UserName"].blank? }.map { |line_h|
          grp_tres_mins = line_h["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h
          data = line_h["Account"].end_with?("-gpu") ? grp_tres_mins["gres/gpu"] : grp_tres_mins["cpu"]
          data.match(/(\d+|N)\((\d+)\)/) { |m| { account: line_h["Account"], used: m[2].to_f / 60, limit: m[1] == "N" ? "N" : m[1].to_f / 60 } }
        }.sort_by { |hash| hash[:account] }
      else
        return false
      end
    end

    return mybalance
  end

  def self.get_myquota(user)
    myquota = CustomCache.fetch("disk_usage/#{user}", expires_in: 24.hours) do
      output = `myquota #{user}`

      if $?.success?
        output
      else
        return false
      end
    end

    return myquota
  end

  def self.get_partition_statuses()
    partition_statuses = CustomCache.fetch("partition_status", expires_in: 5.seconds, race_condition_ttl: 1.seconds) do
      # This script is the updated version of the showpartitions script found on Anvil
      # The source is at https://github.com/OleHolmNielsen/Slurm_tools/blob/master/partitions/showpartitions
      partitions_output, partitions_status = Open3.capture2("sinfo -h -o '%R|%a|%F|%C' -p wholenode,shared,highmem,debug,gpu")
      gpus_output, gpus_status = Open3.capture2("scontrol show node --oneliner | grep -E 'NodeName=g0' | grep -Eo 'CfgTRES=.* AllocTRES=.* C'")

      if partitions_status == 0 && gpus_status == 0
        gpus = gpus_output.split("\n").reduce([0, 0]) { |sum, line|
          m = line.match(/CfgTRES=\S*gpu=(\d) AllocTRES=(?:\S*gpu=(\d))? C/)
          [sum[0] + m[1].to_i, sum[1] + (m[2] || 0).to_i]
        }
        partitions_output.split("\n").map { |line|
          s = line.split("|")
          nodes = s[2].split("/")
          cores = s[3].split("/")
          { partition: s[0], state: s[1], total_nodes: nodes[3], allocated_nodes: nodes[0], other_nodes: nodes[2], free_nodes: nodes[1], total_cores: cores[3], allocated_cores: cores[0], other_cores: cores[2], free_cores: cores[1], allocated_gpus: gpus[1], total_gpus: gpus[0] }
        }
      else
        return false
      end
    end

    return partition_statuses
  end

  def self.get_balance_summary(user, allocation)
    allocations = get_user_allocations(user)

    if !(allocations && allocations.split(",").include?(allocation))
      return :not_in_allocation
    end

    mybalance = CustomCache.fetch("balance_summary/#{allocation}", expires_in: 24.hours) do
      output = `scontrol show assoc accounts=#{allocation} flags=assoc -o`

      if $?.success?
        scontrol_to_hash(output).select { |line_h| !line_h["UserName"].blank? }.map { |line_h|
          grp_tres_mins = line_h["GrpTRESMins"].split(",").map { |pair| pair.split("=") }.to_h
          data = line_h["Account"].end_with?("-gpu") ? grp_tres_mins["gres/gpu"] : grp_tres_mins["cpu"]
          data.match(/(\d+|N)\((\d+)\)/) { |m| { user: line_h["UserName"].split("(")[0], used: m[2].to_f / 60, limit: m[1] == "N" ? "N" : m[1].to_f / 60 } }
        }.sort_by { |hash| -hash[:used] }
      else
        return false
      end
    end

    return mybalance
  end

  def self.get_squeue()
    squeue = CustomCache.fetch("squeue", expires_in: 10.seconds, race_condition_ttl: 2.seconds) do
      output = `squeue -t all -h -o "%i|%P|%j|%u|%T|%r"`

      if $?.success?
        jobs = output.split("\n").map { |job|
          s = job.split("|")
          {
            jobid: s[0],
            partition: s[1],
            name: s[2],
            user: s[3],
            state: s[4],
            reason: s[5],
          }
        }
        jobs
      else
        return false
      end
    end

    return squeue
  end
end
