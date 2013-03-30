Capistrano::Configuration.instance.load do

  _cset :root, "#{deploy_to}/current/public"
  _cset :unicorn_binary, "bundle exec unicorn"
  _cset :unicorn_config, "#{current_path}/config/unicorn.rb"
  _cset :unicorn_pid, "#{current_path}/tmp/pids/unicorn.pid"
  _cset(:deployer) { user }   # deployer must have sudo privileges

  namespace :deploy do
    task :start do ; end
    task :stop do ; end
    task :restart, :roles => :app, :except => { :no_release => true } do
      unicorn.restart
    end
  end

  namespace :unicorn do

    task :start, :roles => :app, :except => { :no_release => true } do 
      run "cd #{current_path} && #{unicorn_binary} -c #{unicorn_config} -E #{rails_env} -D"
    end

    task :stop, :roles => :app, :except => { :no_release => true } do 
      run "kill `cat #{unicorn_pid}`"
    end

    task :graceful_stop, :roles => :app, :except => { :no_release => true } do
      run "kill -s QUIT `cat #{unicorn_pid}`"
    end

    task :reload, :roles => :app, :except => { :no_release => true } do
      run "kill -s USR2 `cat #{unicorn_pid}`"
    end

    task :restart, :roles => :app, :except => { :no_release => true } do
      stop
      start
    end

  end

end
