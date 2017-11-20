require 'rubygems'

active_record_version = ENV["ACTIVE_RECORD_VERSION"] || [">= 2.2.2"]
active_record_version = [active_record_version] unless active_record_version.is_a?(Array)
gem 'activerecord', *active_record_version

require 'active_record'
puts "Testing Against ActiveRecord #{ActiveRecord::VERSION::STRING}" if defined?(ActiveRecord::VERSION)

require File.expand_path(File.join(File.dirname(__FILE__), '..', 'lib', 'seamless_database_pool'))
require File.expand_path(File.join(File.dirname(__FILE__), 'test_model'))

$LOAD_PATH << File.expand_path("../test_adapter", __FILE__)

RSpec.configure do |config|
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  # Run specs in random order to surface order dependencies. If you find an
  # order dependency and want to debug it, you can fix the order by providing
  # the seed, which is printed after each run.
  #     --seed 1234
  config.order = 'random'
  config.expect_with(:rspec) { |c| c.syntax = [:should, :expect] }
  config.mock_with(:rspec) { |c| c.syntax = [:should, :expect] }
end
