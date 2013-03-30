Capistrano::Configuration.instance.load do

  namespace :deploy do
    task :restart, :roles => :app, :except => { :no_release => true } do
      jobs.restart
    end
  end

  namespace :jobs do
    desc "Restart job processes"
    task :restart, :roles => :app, :except => {:no_release => true} do
      run "cd #{current_path} && bundle exec script/job_processor -e #{deploy_env} restart"
    end
  end


