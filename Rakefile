require 'rubygems'
require 'rake'
require 'rake/rdoctask'
require 'yaml'

desc 'Default: run unit tests.'
task :default => :test

begin
  require 'spec/rake/spectask'
  desc 'Test seamless_database_pool.'
  Spec::Rake::SpecTask.new(:test) do |t|
    t.spec_files = FileList.new('spec/**/*_spec.rb')
  end
  
  namespace :test do
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
      Spec::Rake::SpecTask.new(:specified) do |t|
        t.spec_files = FileList.new('spec/connection_adapters_spec.rb')
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
    STDERR.puts "You must have rspec >= 1.3.0 to run the tests"
  end
end

desc 'Generate documentation for seamless_database_pool.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.options << '--title' << 'Seamless Database Pool' << '--line-numbers' << '--inline-source' << '--main' << 'README.rdoc'
  rdoc.rdoc_files.include('README.rdoc')
  rdoc.rdoc_files.include('lib/**/*.rb')
end

begin
  require 'jeweler'
  Jeweler::Tasks.new do |gem|
    gem.name = "seamless_database_pool"
    gem.summary = "Add support for master/slave database clusters in ActiveRecord to improve performance."
    gem.email = "brian@embellishedvisions.com"
    gem.homepage = "http://github.com/bdurand/seamless_database_pool"
    gem.authors = ["Brian Durand"]
    gem.files = FileList["lib/**/*", "spec/**/*", "README.rdoc", "Rakefile"].to_a
    gem.has_rdoc = true
    gem.extra_rdoc_files = ["README.rdoc"]
  
    gem.add_dependency('activerecord', '>= 2.2.2')
    gem.add_development_dependency('rspec', '>= 1.2.9')
    gem.add_development_dependency('jeweler')
  end

  Jeweler::GemcutterTasks.new
rescue LoadError
end