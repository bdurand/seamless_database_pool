module SeamlessDatabasePool
  class Railtie < ::Rails::Railtie
    rake_tasks do
      namespace :db do
        task :load_config do
          # Override seamless_database_pool configuration so db:* rake tasks work as expected.
          original_config = Rails.application.config.database_configuration
          ActiveRecord::Base.configurations = SeamlessDatabasePool.master_database_configuration(original_config)
        end
      end
    end
  end
end
