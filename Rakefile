require 'rubygems'
require 'rake'
require 'yaml'
require "bundler/gem_tasks"

desc 'Default: run unit tests.'
task :default => :test

begin
  require 'rspec'
  require 'rspec/core/rake_task'
  desc 'Run the unit tests'
  RSpec::Core::RakeTask.new(:test)
  
  namespace :test do
    desc "Run all tests including for all database adapters"
    task :all do
      save_val = ENV['TEST_ADAPTERS']
      begin
        ENV['TEST_ADAPTERS'] = YAML.load_file(File.expand_path("../spec/database.yml", __FILE__)).keys.join(' ')
        Rake::Task["test"].execute
      ensure
        ENV['TEST_ADAPTERS'] = save_val
      end
    end
    
    desc "Test all database adapters defined in database.yml or just the one specified in TEST_ADAPTERS"
    task :adapters do
      save_val = ENV['TEST_ADAPTERS']
      begin
        ENV['TEST_ADAPTERS'] ||= YAML.load_file(File.expand_path("../spec/database.yml", __FILE__)).keys.join(' ')
        Rake::Task["test:adapters:specified"].execute
      ensure
        ENV['TEST_ADAPTERS'] = save_val
      end
    end
    
    namespace :adapters do
      desc "Internal task to run database adapter tests"
      RSpec::Core::RakeTask.new(:specified) do |t|
        t.pattern = FileList.new('spec/connection_adapters_spec.rb')
      end
      
      YAML.load_file(File.expand_path("../spec/database.yml", __FILE__)).keys.each do |adapter_name|
        desc "Test the #{adapter_name} database adapter"
        task adapter_name do
          save_val = ENV['TEST_ADAPTERS']
          begin
            ENV['TEST_ADAPTERS'] = adapter_name
            Rake::Task["test:adapters:specified"].execute
          ensure
            ENV['TEST_ADAPTERS'] = save_val
          end
        end
      end
    end
  end
rescue LoadError
  task :test do
    STDERR.puts "You must have rspec >= 2.0 to run the tests"
  end
end
