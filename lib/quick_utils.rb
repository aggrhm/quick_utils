require "active_support"

require "quick_utils/version"
require "quick_utils/task_manager"
require "quick_utils/thread_runner"
require "quick_utils/rails_daemon"
require "quick_utils/rake_daemon"
require "quick_utils/watcher"
require "quick_utils/job"

module QuickUtils
  # Your code goes here...

  def self.unit_of_work(&block)

    work = lambda {
      begin
        block.call
      rescue Exception => e
        if defined? Rails
          Rails.logger.info e
          Rails.logger.info e.backtrace.join("\n\t")
        end
      end
    }

    if defined?(MongoMapper)
      MongoMapper::Plugins::IdentityMap.without(&work)
    elsif defined?(Mongoid)
      Mongoid::unit_of_work({disable: :all}, &work)
    end
  end
end
