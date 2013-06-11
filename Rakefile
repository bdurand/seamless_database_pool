require 'rubygems'
require 'rake'
require 'yaml'

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

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "seamless_database_pool"
    gem.summary = "Add support for master/slave database clusters in ActiveRecord to improve performance."
    gem.email = "bbdurand@gmail.com"
    gem.homepage = "http://github.com/bdurand/seamless_database_pool"
    gem.authors = ["Brian Durand"]
    gem.files = FileList["lib/**/*", "spec/**/*", "README.rdoc", "Rakefile", "MIT-LICENSE"].to_a
    gem.has_rdoc = true
    gem.extra_rdoc_files = ["README.rdoc", "MIT-LICENSE"]
  
    gem.add_dependency('activerecord', '>= 2.2.2')
    gem.add_development_dependency('rspec', '>= 2.0')
    gem.add_development_dependency('jeweler')
    gem.add_development_dependency('sqlite3')
    gem.add_development_dependency('mysql')
    gem.add_development_dependency('pg')
  end

  Jeweler::GemcutterTasks.new
rescue LoadError
end