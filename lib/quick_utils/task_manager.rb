require 'optparse'
require 'ostruct'
require 'logger'

module QuickUtils
  class TaskManager

    def self.run(process_name, args = ARGV, &block)
      t = TaskManager.new(process_name, args, &block)
    end

    def initialize(name, args, &block)
      @process_name = name
      @workers = []
      @options = {:worker_count => 1, :environment => :development, :delay => 5, :root_dir => Dir.pwd}
      class << @options
        def method_missing(m, *args)
          self[m.to_s.gsub('=', '').to_sym] = args[0]
        end
      end
      block.call(@options) if block
      self.process_options(args)
      self.prepare_logger
      self.handle_command
    end

    def process_options(args)
      
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
      end
      
      # If no arguments, give help screen
      @args = optparse.parse!(args.empty? ? ['-h'] : args)

      # additional opts
      @options[:pid_dir] ||= File.join(@options[:root_dir], 'tmp', 'pids')
      @options[:log_dir] ||= File.join(@options[:root_dir], 'log')
    end

    def prepare_logger
      @logger = Logger.new(self.out_log_file)
    end

    def options
      @options
    end

    def handle_command
      return if @args.empty?
      cmd = @args[0].to_sym

      if [:start, :stop, :restart, :run].include?(cmd)
        self.send(cmd)
      else
        abort "Invalid command: #{cmd}"
      end
    end

    def run
      if @options[:rake_task]
        self.run_rake_task(@options[:rake_task])
      end
    end

    def start
      # check if pidfile is running
      if self.pid_is_running?
        puts "Task is running with pid #{self.pid}."
        return
      end

      # fork master and save pid
      puts "Starting #{@process_name}... done."
      Process.daemon
      self.save_pid_file

      # spawn workers
      @state = :up
      $0 = "#{@process_name} : master"
      @logger.info "Started master with pid #{Process.pid}"
      @options[:worker_count].times do |worker_num|
        pid = self.spawn_worker
      end

      # handle signals
      Signal.trap("QUIT") do
        self.shutdown
      end
      Signal.trap("TERM") do
        self.shutdown
      end

      loop do
        if @state == :up
          done_pid = Process.wait
          sleep 3
          @logger.info "Worker #{done_pid} exited. Spawning new worker..."
          @workers.delete(done_pid)
          # spawn new worker
          self.spawn_worker
        end
      end

    end

    def stop
      if !self.pid_is_running?
        puts "No task running."
        return
      end

      # send signal
      Process.kill "QUIT", self.pid
      print "Stopping process #{self.pid}... "

      # check if still running
      while(self.pid_is_running?) do
        sleep 1
      end

      self.delete_pid_file

      print "done.\n"
    end

    def restart
      self.stop
      self.start
    end

    ## WORKER HELPERS

    def spawn_worker
      @logger.info "Spawning new worker..."
      pid = fork
      if pid.nil?
        # we are in the child here
        $0 = "#{@process_name} : worker"
        self.run
        exit!
      end
      @workers << pid
      @logger.info "Spawned worker with pid #{pid}..."
      return pid
    end

    def run_rake_task(task)
      exec "cd #{@options[:root_dir]}; bundle exec rake RAILS_ENV='#{@options[:environment].to_s}' LOG_FILE='#{self.log_file}' #{task}"
    end

    def shutdown
      @logger.info 'Received signal to shutdown. Stopping workers...'
      # stop workers
      @state = :closing
      @workers.each do |pid|
        Process.kill "TERM", pid
      end

      # wait for them to close
      Process.waitall
      @logger.info 'Workers stopped. Exiting.'
      exit
    end

    ## LOG HELPERS

    def log_file
      File.join(@options[:log_dir], "#{@process_name}.log")
    end

    def out_log_file
      File.join(@options[:log_dir], "#{@process_name}.out.log")
    end

    ## PID HELPERS

    def pid_file
      File.join(@options[:pid_dir], "#{@process_name}.pid")
    end

    def pid_file_exists?
      File.exists? self.pid_file
    end

    def pid
      if self.pid_file_exists?
        ret = File.read(self.pid_file).to_i
      else
        ret = nil
      end
      return ret
    end

    def pid_is_running?
      return false if self.pid.nil?
      return system("kill -0 #{self.pid} > /dev/null 2>&1")
    end

    def save_pid_file
      File.open(self.pid_file, 'w') do |fp|
        fp.write(Process.pid)
      end
    end

    def delete_pid_file
      File.delete(self.pid_file)
    end

  end
end

## EXAMPLE
#
# TaskManager.run("job_processor") do |config|
#   config.worker_count = 3
#   config.root_dir = ...
#   config.rake_task = "quick_jobs:process"
# end
#
#
