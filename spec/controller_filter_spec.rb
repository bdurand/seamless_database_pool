require 'spec_helper'

describe "SeamlessDatabasePool::ControllerFilter" do

  module SeamlessDatabasePool
    class TestApplicationController
      attr_reader :session

      def initialize(session)
        @session = session
      end

      def process(action, *args)
        send action
      end

      def redirect_to (options = {}, response_status = {})
        options
      end

      def base_action
        ::SeamlessDatabasePool.read_only_connection_type
      end
    end

    class TestBaseController < TestApplicationController
      include ::SeamlessDatabasePool::ControllerFilter

      use_database_pool :read => :persistent

      def read
        ::SeamlessDatabasePool.read_only_connection_type
      end

      def other
        ::SeamlessDatabasePool.read_only_connection_type
      end
    end

    class TestOtherController < TestBaseController
      use_database_pool :all => :random, [:edit, :save, :redirect_master_action] => :master

      def edit
        ::SeamlessDatabasePool.read_only_connection_type
      end

      def save
        ::SeamlessDatabasePool.read_only_connection_type
      end

      def redirect_master_action
        redirect_to(:action => :read)
      end

      def redirect_read_action
        redirect_to(:action => :read)
      end
    end

    class TestRails2ApplicationController < TestApplicationController
      attr_reader :action_name

      def process(action, *args)
        @action_name = action
        perform_action
      end

      private

      def perform_action
        send action_name
      end
    end

    class TestRails2BaseController < TestRails2ApplicationController
      include ::SeamlessDatabasePool::ControllerFilter

      use_database_pool :read => :persistent

      def read
        ::SeamlessDatabasePool.read_only_connection_type
      end
    end
  end

  let(:session){Hash.new}
  let(:controller){SeamlessDatabasePool::TestOtherController.new(session)}

  it "should work with nothing set" do
    controller = SeamlessDatabasePool::TestApplicationController.new(session)
    controller.process('base_action').should == :master
  end

  it "should allow setting a connection type for a single action" do
    controller = SeamlessDatabasePool::TestBaseController.new(session)
    controller.process('read').should == :persistent
  end

  it "should allow setting a connection type for actions" do
    controller.process('edit').should == :master
    controller.process('save').should == :master
  end

  it "should allow setting a connection type for all actions" do
    controller.process('other').should == :random
  end

  it "should inherit the superclass' options" do
    controller.process('read').should == :persistent
  end

  it "should be able to force using the master connection on the next request" do
    # First request
    controller.process('read').should == :persistent
    controller.send(:use_master_db_connection_on_next_request)

    # Second request
    controller.process('read').should == :master

    # Third request
    controller.process('read').should == :persistent
  end

  it "should not break trying to force the master connection if sessions are not enabled" do
    controller.process('read').should == :persistent
    controller.send(:use_master_db_connection_on_next_request)

    # Second request
    session.clear
    controller.process('read').should == :persistent
  end

  it "should force the master connection on the next request for a redirect in master connection block" do
    controller = SeamlessDatabasePool::TestOtherController.new(session)
    controller.process('redirect_master_action').should == {:action => :read}

    controller.process('read').should == :master
  end

  it "should not force the master connection on the next request for a redirect not in master connection block" do
    controller.process('redirect_read_action').should == {:action => :read}

    controller.process('read').should == :persistent
  end

  it "should work with a Rails 2 controller" do
    controller = SeamlessDatabasePool::TestRails2BaseController.new(session)
    controller.process('read').should == :persistent
  end

  it "marks included methods as private" do
    controller = SeamlessDatabasePool::TestBaseController.new(session)

    controller.public_methods.should_not include(:use_master_db_connection_on_next_request)
    controller.public_methods.should_not include(:seamless_database_pool_options)
    controller.public_methods.should_not include(:set_read_only_connection_for_block)

    controller.protected_methods.should include(:use_master_db_connection_on_next_request)
    controller.protected_methods.should include(:seamless_database_pool_options)
    controller.protected_methods.should include(:set_read_only_connection_for_block)
  end
end
