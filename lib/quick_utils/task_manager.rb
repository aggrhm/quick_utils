require 'optparse'
require 'ostruct'
require 'logger'

module QuickUtils
  class TaskManager

    DURATIONS = {
      second: 1,
      seconds: 1,
      minute: 60,
      minutes: 60,
      hour: 3600,
      hours: 3600,
      day: 86400,
      days: 86400
    }

    def self.run(process_name, args = ARGV, &block)
      t = TaskManager.new(process_name, args, &block)
      t.handle_command
      return t
    end

    attr_accessor :logger, :master_logger

    def initialize(name, args = ARGV, &block)
      @process_name = name
      @workers = []
      @role = :master
      @state = :starting
      @options = {
        :worker_count => 1,
        :environment => (ENV['RAILS_ENV'] || ENV['RAKE_ENV'] || 'development'),
        :delay => 5,
        :root_dir => Dir.pwd,
        :daemon => true
      }
      class << @options
        def add_task(int_num, int_units, &task)
          add_named_task(nil, int_num, int_units, &task)
        end

        def add_named_task(name, int_num, int_units, &task)
          self[:tasks] ||= []
          interval = int_num * DURATIONS[int_units.to_sym]
          self[:tasks] << {name: name, fn: task, interval: interval, last_run_at: nil, next_run_at: Time.now}

        end

        def before_run(&task)
          self[:before_run] = task
        end

        def before_task(&task)
          self[:before_task] = task
        end

        def after_task(&task)
          self[:after_task] = task
        end

        def method_missing(m, *args)
          self[m.to_s.gsub('=', '').to_sym] = args[0]
        end
      end
      block.call(@options) if block
      process_options(args)
      prepare_loggers
    end

    ## ACCESSORS
    
    def options
      @options
    end

    def state
      @state
    end

    ## ACTIONS

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
          @options[:log_level] = :debug
        end
        opts.on('-d', '--delay=D', "Delay between rounds of work (seconds)") do |d|
          @options[:delay] = d
        end
        opts.on('-t', '--test', "Run in test mode") do
          @options[:test_mode] = @options[:debug] = true
          @options[:log_level] = :debug
        end
        opts.on('-D', '--no-daemon', "Run in foreground") do
          @options[:daemon] = false
        end
      end
      
      # If no arguments, give help screen
      @args = optparse.parse!(args.empty? ? ['-h'] : args)

      # additional opts
      if @options[:log_stdout] == true
        @options[:logger] = @options[:master_logger] = Logger.new(STDOUT)
      end
      @options[:pid_dir] ||= File.join(@options[:root_dir], 'tmp', 'pids')
      @options[:log_dir] ||= File.join(@options[:root_dir], 'log')

    end

    def prepare_loggers
      self.logger = @options[:logger] || Logger.new(self.log_file, 1, 1024*1024)
      self.logger.level = @options[:log_level] || :info

      self.master_logger = @options[:master_logger] || Logger.new(self.out_log_file, 1, 1024*1024)
      self.master_logger.level = @options[:log_level] || :info
    end

    def load_rails
      ENV['RAILS_ENV'] = @options[:environment].to_s
      require File.join(@options[:root_dir], 'config', 'environment')
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
      # set global logger
      $logger = logger

      # load rails
      self.load_rails if @options[:load_rails]

      if @options[:before_run]
        @options[:before_run].call(self)
      end

      @state = :running

      if @options[:tasks]
        self.run_tasks(@options[:tasks])
      elsif @options[:rake_task]
        self.run_rake_task(@options[:rake_task])
      end
    end

    def start
      # check if pidfile is running
      if self.pid_is_running?
        puts "Task is already running with pid #{self.pid}."
        return
      end

      # fork master and save pid
      puts "Starting #{@process_name}... done."
      Signal.trap 'HUP', 'IGNORE'   # ignore hup for now
      Process.daemon if @options[:daemon] == true
      self.save_pid_file

      # handle signals
      self.handle_signals

      # spawn workers
      $0 = "#{@process_name} : master"
      master_logger.info "Started master with pid #{Process.pid}"
      @options[:worker_count].times do |worker_num|
        pid = self.spawn_worker
      end

      # watch workers
      @state = :watching
      loop do
        done_pid = Process.wait
        sleep 3
        master_logger.info "Worker #{done_pid} exited. Spawning new worker..."
        @workers.delete(done_pid)
        # spawn new worker
        self.spawn_worker
      end

    end

    def stop
      @state = :stopping
      if !self.pid_is_running?
        puts "No task running."
        return
      end

      # send signal
      Process.kill "TERM", self.pid
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
      master_logger.info "Spawning new worker..."
      pid = fork
      if pid.nil?
        @role = :worker
        # we are in the child here
        $0 = "#{@process_name} : worker"
        self.run
        master_logger.info "Worker run ended cleanly. Exiting."
        exit!
      end
      @workers << pid
      master_logger.info "Spawned worker with pid #{pid}."
      return pid
    end

    def run_rake_task(task)
      exec "cd #{@options[:root_dir]}; bundle exec rake RAILS_ENV='#{@options[:environment].to_s}' LOG_FILE='#{self.log_file}' #{task}"
    end

    def run_tasks(tasks)
      # setup logger
      Rails.logger = self.logger if defined?(Rails)
      Moped.logger = nil if defined?(Moped)
      self.logger.info "Starting #{@process_name} task manager for #{@options[:environment]}"

      # loop ready tasks
      before_task = @options[:before_task]
      after_task = @options[:after_task]
      log_tasks = @options[:log_task_scheduling] == true
      loop do
        if @state != :running
          master_logger.info "Stopping run loop cleanly..."
          break
        end
        tasks.each do |task|
          if task[:next_run_at] < Time.now
            begin
              self.logger.info("Starting task #{task[:name]}.") if log_tasks
              before_task.call(self, task) if !before_task.nil?
              task[:fn].call(self)
              after_task.call(self, task) if !after_task.nil?
              self.logger.info("Finished task #{task[:name]}.") if log_tasks
            rescue => e
              logger.info e.message
              logger.info e.backtrace.join("\n\t")
            ensure
              task[:last_run_at] = Time.now
              task[:next_run_at] = Time.now + task[:interval]
            end
          end
        end
        sleep 1
      end
    end

    def handle_signals
      Signal.trap("QUIT") {
        master_logger.info "(#{@role.to_s}) Received SIGQUIT. Shutting down."
        self.shutdown(signal: "SIGQUIT")
      }
      Signal.trap("INT") {
        master_logger.info "(#{@role.to_s}) Received SIGINT. Shutting down."
        self.shutdown(signal: "SIGINT")
      }
      Signal.trap("TERM") {
        master_logger.info "(#{@role.to_s}) Received SIGTERM. Shutting down."
        self.shutdown(signal: "SIGTERM")
      }
      Signal.trap("HUP") { 
        master_logger.info "(#{@role.to_s}) Received SIGHUP. Shutting down."
        self.shutdown(signal: "SIGHUP")
      }
    end

    def shutdown(opts={})
      if @role == :master
        master_logger.info 'Master received signal to shutdown. Stopping workers...'
        # stop workers
        @state = :stopping
        @workers.each do |pid|
          Process.kill "TERM", pid
        end

        # wait for them to close
        Process.waitall
        master_logger.info 'Workers stopped. Exiting.'
        delete_pid_file
        exit
      else
        # if worker, just set state and let loop end on its own cleanly
        master_logger.info 'Worker received signal to shutdown. Preparing to stop cleanly.'
        @state = :stopping
        if @options[:raise_interrupt] == true
          raise Interrupt.new(opts[:signal])
        end
      end
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
      File.delete(self.pid_file) if File.exists?(self.pid_file)
    end

  end
end

## EXAMPLE
#
# TaskManager.run("job_processor") do |config|
#   config.worker_count = 3
#   config.root_dir = ...
#   config.load_rails = true
#
#   -- for rake task
#   config.rake_task = "quick_jobs:process"
#
#   -- for ruby methods
#   config.add_task (3, :seconds) do 
#     Job.process_jobs
#   end
#
#   config.add_task (1, :days) do
#     Subscription.process_active_expired
#   end
#
#   ]
# end
#
#
