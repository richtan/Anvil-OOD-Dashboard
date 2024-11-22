require "util"

module Purdue
  class Balance
    def self.mybalance()
      @mybalance ||= build_balance()
    end

    def self.build_balance()
      #return Util.get_mybalance(Util.get_user).map { |hash| "#{hash[:account]} #{sprintf("%.1f", hash[:used])}" }
    end
  end

  class Lmod
    def self.lmod(mod)
      @lmod ||= Hash.new do |h, key|
        Rails.logger.warn "executing expensive module"
        h[key] = build_lmod(key)
      end

      @lmod[mod]
    end

    def self.build_lmod(mod)
      cmd = "module_avail_terse #{mod}"
      output, status = Open3.capture2e(cmd)
      output.split("\n").map(&:strip).reject(&:blank?).sort
    end
  end
end
