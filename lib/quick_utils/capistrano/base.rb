Capistrano::Configuration.instance.load do

  ## App settings
  
  _cset(:app_name) { abort("Please specify application name") }
  _cset(:deploy_env) { abort("Please specify deployment stage") }
  _cset :user, 'login'

  set(:application) { "#{app_name}-#{deploy_env}" }
  _cset(:app_dir) { "/var/www/#{application}" }
  _cset(:rails_env) { deploy_env }
  _cset :deploy_via, 'remote_cache'
  _cset :use_sudo, false
  set(:deploy_to) { app_dir }

  ## SCM settings

  _cset(:repository) { abort("Specify the location of the repository") }
  _cset :branch, 'master'

  _cset :scm, :git
  _cset :scm_verbose, true

  default_run_options[:pty] = true
  default_run_options[:shell] = false
  ssh_options[:forward_agent] = true

end

# Helper methods
def _cset(name, *args, &block)
  unless exists?(name)
    set(name, *args, &block)
  end
end

def close_sessions
	sessions.values.each { |session| session.close }
	sessions.clear
end

def create_tmp_file(contents)
	system 'mkdir tmp'
	file = File.new("tmp/#{application}", "w")
	file << contents
	file.close
end

