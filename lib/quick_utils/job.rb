module QuickUtils
	module Job
		extend ActiveSupport::Concern

		module ClassMethods
			def job_mongo_keys!
				key :jt,  Integer                   # job type
				key :pr,  Integer, :default => 0    # priority
				key :ip,  Boolean, :default => false  # in process
				key :opt, Hash

				attr_alias :job_type, :jt
				attr_alias :priority, :pr
				attr_alias :in_progress, :ip
				cattr_accessor :job_types
				self.job_types = {}
						
				# NAMED SCOPES
				scope :with_job_type, lambda { |job_type|
					where(:jt => job_type)
				}
				scope :processing, lambda {
					where(:ip => true)
				}
				scope :unprocessed, lambda {
					where(:ip => false)
				}
				scope :by_priority, lambda {
					sort(:pr.asc)
				}

				timestamps!
			end

			def ready_for(jt)
				self::with_job_type(self::job_types[jt]).unprocessed
			end
		end

		module InstanceMethods
			def is_processing?
				self.ip == true
			end

			def processing!
				self.ip = true
				self.save
			end
		end

	end
end
