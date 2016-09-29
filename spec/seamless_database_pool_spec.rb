require 'spec_helper'

describe "SeamlessDatabasePool" do

  before(:each) do
    SeamlessDatabasePool.clear_read_only_connection
  end
  
  after(:each) do
    SeamlessDatabasePool.clear_read_only_connection
  end
  
  it "should use the master connection by default" do
    connection = double(:connection, :master_connection => :master_db_connection, :using_master_connection? => false)
    SeamlessDatabasePool.read_only_connection_type.should == :master
    SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
  end
  
  it "should be able to set using persistent read connections" do
    connection = double(:connection)
    connection.should_receive(:random_read_connection).once.and_return(:read_db_connection)
    connection.stub(:using_master_connection? => false)
    SeamlessDatabasePool.use_persistent_read_connection
    SeamlessDatabasePool.read_only_connection_type.should == :persistent
    SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
    SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
  end
  
  it "should be able to set using random read connections" do
    connection = double(:connection)
    connection.should_receive(:random_read_connection).and_return(:read_db_connection_1, :read_db_connection_2)
    connection.stub(:using_master_connection? => false)
    SeamlessDatabasePool.use_random_read_connection
    SeamlessDatabasePool.read_only_connection_type.should == :random
    SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection_1
    SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection_2
  end
  
  it "should use the master connection if the connection is forcing it" do
    connection = double(:connection, :master_connection => :master_db_connection)
    connection.should_receive(:using_master_connection?).and_return(true)
    SeamlessDatabasePool.use_persistent_read_connection
    SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
  end
  
  it "should be able to set using the master connection" do
    connection = double(:connection, :master_connection => :master_db_connection)
    connection.stub(:using_master_connection? => false)
    SeamlessDatabasePool.use_master_connection
    SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
  end
  
  it "should be able to use persistent read connections within a block" do
    connection = double(:connection, :master_connection => :master_db_connection)
    connection.should_receive(:random_read_connection).once.and_return(:read_db_connection)
    connection.stub(:using_master_connection? => false)
    SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
    SeamlessDatabasePool.use_persistent_read_connection do
      SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
      SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
      :test_val
    end.should == :test_val
    SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
  end
  
  it "should be able to use random read connections within a block" do
    connection = double(:connection, :master_connection => :master_db_connection)
    connection.should_receive(:random_read_connection).and_return(:read_db_connection_1, :read_db_connection_2)
    connection.stub(:using_master_connection? => false)
    SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
    SeamlessDatabasePool.use_random_read_connection do
      SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection_1
      SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection_2
        :test_val
      end.should == :test_val
    SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
  end
  
  it "should be able to use the master connection within a block" do
    connection = double(:connection, :master_connection => :master_db_connection)
    connection.should_receive(:random_read_connection).once.and_return(:read_db_connection)
    connection.stub(:using_master_connection? => false)
    SeamlessDatabasePool.use_persistent_read_connection
    SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
    SeamlessDatabasePool.use_master_connection do
      SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
        :test_val
      end.should == :test_val
    SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
    SeamlessDatabasePool.clear_read_only_connection
  end
  
  it "should be able to use connection blocks within connection blocks" do
    connection = double(:connection, :master_connection => :master_db_connection)
    connection.stub(:random_read_connection => :read_db_connection)
    connection.stub(:using_master_connection? => false)
    SeamlessDatabasePool.use_persistent_read_connection do
      SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
      SeamlessDatabasePool.use_master_connection do
        SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
        SeamlessDatabasePool.use_random_read_connection do
          SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
        end
        SeamlessDatabasePool.read_only_connection(connection).should == :master_db_connection
      end
    end
    SeamlessDatabasePool.clear_read_only_connection
  end
  
  it "should be able to change the persistent connection" do
    connection = double(:connection)
    connection.stub(:random_read_connection => :read_db_connection, :using_master_connection? => false)
    
    SeamlessDatabasePool.use_persistent_read_connection
    SeamlessDatabasePool.read_only_connection_type.should == :persistent
    SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
    SeamlessDatabasePool.set_persistent_read_connection(connection, :another_db_connection)
    SeamlessDatabasePool.read_only_connection(connection).should == :another_db_connection
    
    SeamlessDatabasePool.use_random_read_connection
    SeamlessDatabasePool.read_only_connection_type.should == :random
    SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
    SeamlessDatabasePool.set_persistent_read_connection(connection, :another_db_connection)
    SeamlessDatabasePool.read_only_connection(connection).should == :read_db_connection
  end
  
  it "should be able to specify a default read connection type instead of :master" do
    SeamlessDatabasePool.read_only_connection_type.should == :master
    SeamlessDatabasePool.read_only_connection_type(nil).should == nil
  end
  
  it "should pull out the master configurations for compatibility with rake db:* tasks" do
    config = {
      'development' => {
        'adapter' => 'seamless_database_pool',
        'pool_adapter' => 'mysql2',
        'database' => 'development',
        'username' => 'root',
        'master' => {
          'host' => 'localhost',
          'pool_weight' => 2
        },
        'read_pool' => {
          'host' => 'slavehost',
          'pool_weight' => 5
        }
      },
      'test' => {
        'adapter' => 'mysql2',
        'database' => 'test'
      }
    }
    SeamlessDatabasePool.master_database_configuration(config).should == {
      'development' => {
        'adapter' => 'mysql2',
        'database' => 'development',
        'username' => 'root',
        'host' => 'localhost'
      },
      'test' => {
        'adapter' => 'mysql2',
        'database' => 'test'
      }
    }
  end
end
