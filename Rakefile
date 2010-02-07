require 'rubygems'
require 'rake'
require 'rake/rdoctask'

desc 'Default: run unit tests.'
task :default => :test

begin
  require 'spec/rake/spectask'
  desc 'Test seamless_database_pool.'
  Spec::Rake::SpecTask.new(:test) do |t|
    t.spec_files = FileList.new('spec/**/*_spec.rb')
  end
rescue LoadError
  tast :test do
    STDERR.puts "You must have rspec >= 1.2.9 to run the tests"
  end
end

desc 'Generate documentation for seamless_database_pool.'
Rake::RDocTask.new(:rdoc) do |rdoc|
  rdoc.rdoc_dir = 'rdoc'
  rdoc.options << '--title' << 'Seamless Database Pool' << '--line-numbers' << '--inline-source' << '--main' << 'README'
  rdoc.rdoc_files.include('README')
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
  
    gem.add_dependency('activerecord', '>= 2.2.2')
    gem.add_development_dependency('rspec', '>= 1.2.9')
    gem.add_development_dependency('jeweler')
  end

  Jeweler::GemcutterTasks.new
rescue LoadError
end