module QuickUtils
	class Watcher < RailsDaemon
		def self.set_app_name(app_name)
			@@main_proc = app_name
		end

		def self.set_proc_list(plist)
			@@processes = plist
		end

		def run(worker_name = nil)

			logger = Logger.new(@@log_file)

			while true
				# get num thins running
				thin_num = `ps -ef | grep "thin" | grep "#{@@main_proc}" | grep -v "grep" | wc | awk '{print $1}'`.to_i
				needs_restart = false
				@@processes.each do |proc|
					pnum = `ps -ef | grep "#{proc}" | grep -v "grep" | wc | awk '{print $1}'`.to_i
					needs_restart ||= (pnum == 0)
				end
				if thin_num == 0 || needs_restart
					logger.info("Restarting #{main_proc} now...");
					system "cd #{@@rails_root}; bundle exec script/restart;"
				end
				sleep @options[:delay]
			end
				
		end
	end
end
