Capistrano::Configuration.instance.load do

  _cset :sites_available, '/opt/nginx/conf/sites-available'
  _cset :sites_enabled, '/opt/nginx/conf/sites-enabled'
  _cset :listen, 80
  _cset :root, "#{deploy_to}/current/public"
  _cset(:server_name) { abort "Please enter a server_name directive for nginx" }
  _cset(:deployer) { user }   # deployer must have sudo privileges

  namespace :deploy do
    task :start do ; end
    task :stop do ; end
    task :restart, :roles => :app, :except => { :no_release => true } do
      # nginx.reload_application might not work under some scenarios. 
      # nginx.restart is used instead.
      # nginx.reload_application
      nginx.restart
      jobs.restart
    end
  end

  namespace :jobs do
    desc "Restart job processes"
    task :restart, :roles => :app, :except => {:no_release => true} do
      run "cd #{current_path} && ./script/restart_jobs #{deploy_env}"
    end
  end

  namespace :nginx do

    desc "Create the application deployment directory under /var/www"
    task :prepare, :roles => :app, :except => { :no_release => true } do
      run "test -d #{deploy_to} || mkdir -p #{deploy_to}"
      set :old_user, "#{user}" 
      set :user, "#{deployer}" 
      close_sessions
      run "sudo sh -c \"test -f #{sites_available}/#{application}.conf || cp #{sites_available}/default.conf.template #{sites_available}/#{application}.conf\""
      run "sudo sh -c \"test -L #{sites_enabled}/#{application}.conf || ln -s #{sites_available}/#{application}.conf #{sites_enabled}/#{application}.conf\""
      run "sudo sh -c \"sed -i -e's|%listen%|#{listen}|g' #{sites_available}/#{application}.conf\""
      run "sudo sh -c \"sed -i -e's|%server_name%|#{server_name}|g' #{sites_available}/#{application}.conf\""
      run "sudo sh -c \"sed -i -e's|%root%|#{root}|g' #{sites_available}/#{application}.conf\""
      run "sudo sh -c \"sed -i -e's|%rails_env%|#{rails_env}|g' #{sites_available}/#{application}.conf\""
      set :user, "#{old_user}"
      close_sessions
    end

    desc "Restart Nginx"
    task :restart, :roles => :app, :except => { :no_release => true } do
      set :old_user, "#{user}" 
      set :user, "#{deployer}" 
      close_sessions
      run "/usr/bin/sudo /usr/bin/service nginx restart"
      set :user, "#{old_user}"
      close_sessions
    end

    desc "Stop Nginx"
    task :stop, :roles => :app, :except => { :no_release => true } do
      set :old_user, "#{user}" 
      set :user, "#{deployer}" 
      run "/usr/bin/sudo /usr/sbin/service nginx stop"
      set :user, "#{old_user}"
      close_sessions
    end

    desc "Start Nginx"
    task :start, :roles => :app, :except => { :no_release => true } do
      set :old_user, "#{user}" 
      set :user, "#{deployer}" 
      run "/usr/bin/sudo /usr/sbin/service nginx start"
      set :user, "#{old_user}"
      close_sessions
    end

    desc "Request to reload the application"
    task :reload_application, :roles => :app, :except => { :no_release => true } do
      run "touch #{File.join(current_path,'tmp','restart.txt')}"
    end

    desc "Remove a virtual host"
    task :remove_virtual_host, :roles => :app, :except => { :no_release => true } do
      set :old_user, "#{user}" 
      set :user, "#{deployer}" 
      run "/usr/bin/sudo /usr/sbin/service nginx stop"
      run "/usr/bin/sudo rm -f #{sites_enabled}/#{application}.conf"
      run "/usr/bin/sudo rm -f #{sites_available}/#{application}.conf"
      run "/usr/bin/sudo /usr/sbin/service nginx start"
      set :user, "#{old_user}"
      close_sessions
    end

    desc "Disable a virtual host"
    task :disable_virtual_host, :roles => :app, :except => { :no_release => true } do
      set :old_user, "#{user}" 
      set :user, "#{deployer}" 
      run "/usr/bin/sudo /usr/sbin/service nginx stop"
      run "/usr/bin/sudo rm -f #{sites_enabled}/#{application}.conf"
      run "/usr/bin/sudo /usr/sbin/service nginx start"
      set :user, "#{old_user}"
      close_sessions
    end

    desc "Remove the application"
    task :remove_application, :roles => :app, :except => { :no_release => true } do
      set :old_user, "#{user}" 
      set :user, "#{deployer}" 
      run "/usr/bin/sudo /usr/sbin/service nginx stop"
      run "/usr/bin/sudo rm -f #{sites_enabled}/#{application}.conf"
      run "/usr/bin/sudo rm -f #{sites_available}/#{application}.conf"
      run "/usr/bin/sudo rm -rf #{deploy_to}"
      run "/usr/bin/sudo /usr/sbin/service nginx start"
      set :user, "#{old_user}"
      close_sessions
    end
  end

  before "deploy:setup", "nginx:prepare"
  

end
