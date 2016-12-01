module SeamlessDatabasePool
  class Railtie < ::Rails::Railtie
    rake_tasks do
      namespace :db do
        task :load_config do
          # Override seamless_database_pool configuration so db:* rake tasks work as expected.
          module DatabaseConfiguration
            def configurations
              SeamlessDatabasePool.master_database_configuration(super.deep_dup)
            end
          end
          ActiveRecord::Base.singleton_class.prepend(DatabaseConfiguration)
        end
      end
    end
  end
end
