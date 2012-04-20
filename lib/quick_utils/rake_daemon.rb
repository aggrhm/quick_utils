module QuickUtils
	class RakeDaemon < RailsDaemon

		@@rake_task = ''

		def self.set_rake_task(task)
			@@rake_task = task
		end

		def run(worker_name = nil)

			ENV['RAILS_ENV'] = @options[:environment].to_s
			ENV['LOG_FILE'] = @@log_file

			system "cd #{@@rails_root}; exec rake RAILS_ENV='#{@options[:environment].to_s}' LOG_FILE='#{@@log_file}' #{@@rake_task}"
			
		end
	end
end
