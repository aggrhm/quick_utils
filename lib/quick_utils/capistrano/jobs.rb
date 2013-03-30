Capistrano::Configuration.instance.load do

  namespace :jobs do
    desc "Restart job processes"
    task :restart, :roles => :app, :except => {:no_release => true} do
      run "cd #{current_path} && bundle exec script/job_processor -e #{deploy_env} restart"
    end
  end

  after "deploy:restart", "jobs:restart"

end
