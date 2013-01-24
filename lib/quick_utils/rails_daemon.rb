require 'rubygems'
require 'daemons'
require 'optparse'
require 'logger'
require 'fileutils'

module QuickUtils
	class RailsDaemon

		@@proc_name = ''
		@@log_file = ''
		@@rails_root = Dir.pwd

		def self.set_process_name(pname)
			@@proc_name = pname
			@@log_file = File.join(@@rails_root, 'log', "#{@@proc_name}.log")
		end

		def self.set_rails_root(dir)
			@@rails_root = dir
		end
		
		def initialize(args)
			@options = {:worker_count => 1, :environment => :development, :delay => 5, :stage => :development}
			
			optparse = OptionParser.new do |opts|
				opts.banner = "Usage: #{File.basename($0)} [options] start|stop|restart|run"

				opts.on('-h', '--help', 'Show this message') do
					puts opts
					exit 1
				end
				opts.on('-e', '--environment=NAME', 'Specifies the environment to run this apn_sender under ([development]/production).') do |e|
					@options[:environment] = e
				end
				opts.on('-n', '--number-of-workers=WORKERS', "Number of unique workers to spawn") do |worker_count|
					@options[:worker_count] = worker_count.to_i rescue 1
				end
				opts.on('-v', '--verbose', "Turn on verbose mode") do
					@options[:verbose] = true
				end
				opts.on('-d', '--delay=D', "Delay between rounds of work (seconds)") do |d|
					@options[:delay] = d
				end
				opts.on('-s', '--stage=NAME', "Stage ([development]/staging/production)") do |s|
					@options[:stage] = s
				end
			end
			
			# If no arguments, give help screen
			@args = optparse.parse!(args.empty? ? ['-h'] : args)
		end

		def daemonize
      pids_dir = File.join(@@rails_root, 'tmp', 'pids')
      FileUtils.mkdir_p pids_dir

			@options[:worker_count].times do |worker_index|
				process_name = @options[:worker_count] == 1 ? @@proc_name : "#{@@proc_name}.#{worker_index}"
				Daemons.run_proc(process_name, :dir => pids_dir, :dir_mode => :normal, :ARGV => @args) do |*args|
					run process_name
				end
			end
		end

		def run(worker_name = nil)

		end
	end
end
