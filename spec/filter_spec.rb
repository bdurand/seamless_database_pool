require File.expand_path(File.join(File.dirname(__FILE__), 'spec_helper'))
require 'cgi'

describe "SeamlessDatabasePool::ControllerFilter" do
  
  module SeamlessDatabasePool
    class TestApplicationController
      attr_reader :action_name, :session
      
      def initialize(action, session = nil)
        @action_name = action
        session ||= {}
        @session = session
      end
      
      def perform_action
        send action_name
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
  end
  
  it "should work with nothing set" do
    controller = SeamlessDatabasePool::TestApplicationController.new('base_action')
    controller.perform_action.should == :master
  end
  
  it "should allow setting a connection type for a single action" do
    controller = SeamlessDatabasePool::TestBaseController.new('read')
    controller.perform_action.should == :persistent
  end
  
  it "should allow setting a connection type for actions" do
    controller = SeamlessDatabasePool::TestOtherController.new('edit')
    controller.perform_action.should == :master
    controller = SeamlessDatabasePool::TestOtherController.new('save')
    controller.perform_action.should == :master
  end
  
  it "should allow setting a connection type for all actions" do
    controller = SeamlessDatabasePool::TestOtherController.new('other')
    controller.perform_action.should == :random
  end
  
  it "should inherit the superclass' options" do
    controller = SeamlessDatabasePool::TestOtherController.new('read')
    controller.perform_action.should == :persistent
  end
  
  it "should be able to force using the master connection on the next request" do
    session = {}
    
    # First request
    controller = SeamlessDatabasePool::TestOtherController.new('read', session)
    controller.perform_action.should == :persistent
    controller.use_master_db_connection_on_next_request
    
    # Second request
    controller = SeamlessDatabasePool::TestOtherController.new('read', session)
    controller.perform_action.should == :master
    
    # Third request
    controller = SeamlessDatabasePool::TestOtherController.new('read', session)
    controller.perform_action.should == :persistent
  end
  
  it "should not break trying to force the master connection if sessions are not enabled" do
    controller = SeamlessDatabasePool::TestOtherController.new('read', nil)
    controller.perform_action.should == :persistent
    controller.use_master_db_connection_on_next_request
    
    # Second request
    controller = SeamlessDatabasePool::TestOtherController.new('read', nil)
    controller.perform_action.should == :persistent
  end
  
  it "should force the master connection on the next request for a redirect in master connection block" do
    session = {}
    controller = SeamlessDatabasePool::TestOtherController.new('redirect_master_action', session)
    controller.perform_action.should == {:action => :read}
    
    controller = SeamlessDatabasePool::TestOtherController.new('read', session)
    controller.perform_action.should == :master
  end

  it "should not force the master connection on the next request for a redirect not in master connection block" do
    session = {}
    controller = SeamlessDatabasePool::TestOtherController.new('redirect_read_action', session)
    controller.perform_action.should == {:action => :read}
    
    controller = SeamlessDatabasePool::TestOtherController.new('read', session)
    controller.perform_action.should == :persistent
  end
  
end
