require 'spec_helper'

module SeamlessDatabasePool
  class MockConnection < ActiveRecord::ConnectionAdapters::AbstractAdapter
    def initialize (name)
      @name = name
    end
    
    def inspect
      "#{@name} connection"
    end
    
    def reconnect!
      sleep(0.1)
    end
    
    def active?
      true
    end
    
    def begin_db_transaction
    end
    
    def commit_db_transaction
    end
  end
  
  class MockMasterConnection < MockConnection
    def insert (sql, name = nil); end
    def update (sql, name = nil); end
    def execute (sql, name = nil); end
    def columns (table_name, name = nil); end
  end
end

describe "SeamlessDatabasePoolAdapter ActiveRecord::Base extension" do

  it "should establish the connections in the pool merging global options into the connection options" do
    options = {
      :adapter => 'seamless_database_pool',
      :pool_adapter => 'reader',
      :username => 'user',
      :master => {
        'adapter' => 'writer',
        'host' => 'master_host'
      },
      :read_pool => [
        {'host' => 'read_host_1'},
        {'host' => 'read_host_2', 'pool_weight' => '2'},
        {'host' => 'read_host_3', 'pool_weight' => '0'}
      ]
    }
    
    pool_connection = double(:connection)
    master_connection = SeamlessDatabasePool::MockConnection.new("master")
    read_connection_1 = SeamlessDatabasePool::MockConnection.new("read_1")
    read_connection_2 = SeamlessDatabasePool::MockConnection.new("read_2")
    logger = ActiveRecord::Base.logger
    weights = {master_connection => 1, read_connection_1 => 1, read_connection_2 => 2}
    
    expect(ActiveRecord::Base).to receive(:writer_connection).with('adapter' => 'writer', 'host' => 'master_host', 'username' => 'user', 'pool_weight' => 1).and_return(master_connection)
    expect(ActiveRecord::Base).to receive(:reader_connection).with('adapter' => 'reader', 'host' => 'read_host_1', 'username' => 'user', 'pool_weight' => 1).and_return(read_connection_1)
    expect(ActiveRecord::Base).to receive(:reader_connection).with('adapter' => 'reader', 'host' => 'read_host_2', 'username' => 'user', 'pool_weight' => 2).and_return(read_connection_2)
    
    klass = double(:class)
    expect(ActiveRecord::ConnectionAdapters::SeamlessDatabasePoolAdapter).to receive(:adapter_class).with(master_connection).and_return(klass)
    expect(klass).to receive(:new).with(nil, logger, master_connection, [read_connection_1, read_connection_2], weights, options).and_return(pool_connection)
    
    expect(ActiveRecord::Base).to receive(:establish_adapter).with('writer')
    expect(ActiveRecord::Base).to receive(:establish_adapter).with('reader').twice
    
    ActiveRecord::Base.seamless_database_pool_connection(options).should == pool_connection
  end
  
  it "should raise an error if the adapter would be recursive" do
    lambda{ActiveRecord::Base.seamless_database_pool_connection('seamless_database_pool').should_raise(ActiveRecord::AdapterNotFound)}
  end
end

describe "SeamlessDatabasePoolAdapter" do
  
  let(:master_connection){ SeamlessDatabasePool::MockMasterConnection.new("master") }
  let(:read_connection_1){ SeamlessDatabasePool::MockConnection.new("read_1") }
  let(:read_connection_2){ SeamlessDatabasePool::MockConnection.new("read_2") }
  let(:config){ {} }
  let(:pool_connection) do
    weights = {master_connection => 1, read_connection_1 => 1, read_connection_2 => 2}
    connection_class = ActiveRecord::ConnectionAdapters::SeamlessDatabasePoolAdapter.adapter_class(master_connection)
    connection_class.new(nil, nil, master_connection, [read_connection_1, read_connection_2], weights, config)
  end
  
  it "should be able to be converted to a string" do
    pool_connection.to_s.should =~ /\A#<ActiveRecord::ConnectionAdapters::SeamlessDatabasePoolAdapter::Abstract:0x[0-9a-f]+ 3 connections>\z/
    pool_connection.inspect.should == pool_connection.to_s
  end
  
  context "selecting a connection from the pool" do
    it "should initialize the connection pool" do
      pool_connection.master_connection.should == master_connection
      pool_connection.read_connections.should == [read_connection_1, read_connection_2]
      pool_connection.all_connections.should == [master_connection, read_connection_1, read_connection_2]
      pool_connection.pool_weight(master_connection).should == 1
      pool_connection.pool_weight(read_connection_1).should == 1
      pool_connection.pool_weight(read_connection_2).should == 2
    end
  
    it "should return the current read connection" do
      expect(SeamlessDatabasePool).to receive(:read_only_connection).with(pool_connection).and_return(:current)
      pool_connection.current_read_connection.should == :current
    end
  
    it "should select a random read connection" do
      mock_connection = double(:connection)
      mock_connection.stub(:active? => true)
      expect(pool_connection).to receive(:available_read_connections).and_return([:fake1, :fake2, mock_connection])
      expect(pool_connection).to receive(:rand).with(3).and_return(2)
      pool_connection.random_read_connection.should == mock_connection
    end
  
    it "should select the master connection if the read pool is empty" do
      expect(pool_connection).to receive(:available_read_connections).and_return([])
      pool_connection.random_read_connection.should == master_connection
    end
  
    it "should use the master connection in a block" do
      connection_class = ActiveRecord::ConnectionAdapters::SeamlessDatabasePoolAdapter.adapter_class(master_connection)
      connection = connection_class.new(nil, double(:logger), master_connection, [read_connection_1], {read_connection_1 => 1}, config)
      connection.random_read_connection.should == read_connection_1
      connection.use_master_connection do
        connection.random_read_connection.should == master_connection
      end
      connection.random_read_connection.should == read_connection_1
    end
  
    it "should use the master connection inside a transaction" do
      connection_class = ActiveRecord::ConnectionAdapters::SeamlessDatabasePoolAdapter.adapter_class(master_connection)
      connection = connection_class.new(nil, double(:logger), master_connection, [read_connection_1], {read_connection_1 => 1}, config)
      expect(master_connection).to receive(:begin_db_transaction)
      expect(master_connection).to receive(:commit_db_transaction)
      expect(master_connection).to receive(:select).with('Transaction SQL', nil)
      expect(read_connection_1).to receive(:select).with('SQL 1', nil)
      expect(read_connection_1).to receive(:select).with('SQL 2', nil)
    
      SeamlessDatabasePool.use_persistent_read_connection do
        connection.send(:select, 'SQL 1', nil)
        connection.transaction do
          connection.send(:select, 'Transaction SQL', nil)
        end
        connection.send(:select, 'SQL 2', nil)
      end
    end
  end
  
  context "read connection methods" do
    it "should proxy select methods to a read connection" do
      expect(pool_connection).to receive(:current_read_connection).and_return(read_connection_1)
      expect(read_connection_1).to receive(:select).with('SQL').and_return(:retval)
      pool_connection.send(:select, 'SQL').should == :retval
    end
  
    it "should proxy execute methods to a read connection" do
      expect(pool_connection).to receive(:current_read_connection).and_return(read_connection_1)
      expect(read_connection_1).to receive(:execute).with('SQL').and_return(:retval)
      pool_connection.execute('SQL').should == :retval
    end
  
    it "should proxy select_rows methods to a read connection" do
      expect(pool_connection).to receive(:current_read_connection).and_return(read_connection_1)
      expect(read_connection_1).to receive(:select_rows).with('SQL').and_return(:retval)
      pool_connection.select_rows('SQL').should == :retval
    end
  end
  
  context "master connection methods" do
    it "should proxy insert method to the master connection" do
      expect(master_connection).to receive(:insert).with('SQL').and_return(:retval)
      pool_connection.insert('SQL').should == :retval
    end
  
    it "should proxy update method to the master connection" do
      expect(master_connection).to receive(:update).with('SQL').and_return(:retval)
      pool_connection.update('SQL').should == :retval
    end
  
    it "should proxy columns method to the master connection" do
      expect(master_connection).to receive(:columns).with(:table).and_return(:retval)
      pool_connection.columns(:table).should == :retval
    end
  end
  
  context "fork to all connections" do
    context "when read-only connection type is master" do
      it "should fork active? to master connection only" do
        expect(master_connection).to receive(:active?).and_return(true)
        expect(read_connection_1).not_to receive(:active?)
        expect(read_connection_2).not_to receive(:active?)
        pool_connection.active?.should == true
      end

      it "should fork verify! to master connection only" do
        expect(master_connection).to receive(:verify!).with(5)
        expect(read_connection_1).not_to receive(:verify!)
        expect(read_connection_2).not_to receive(:verify!)
        pool_connection.verify!(5)
      end
    end

    context "When read-only connection type is persistent or random" do
      around do |example|
        SeamlessDatabasePool.set_read_only_connection_type(:persistent) do
          example.run
        end
        SeamlessDatabasePool.set_read_only_connection_type(:random) do
          example.run
        end
      end

      it "should fork active? to all connections and return true if all are up" do
        expect(master_connection).to receive(:active?).and_return(true)
        expect(read_connection_1).to receive(:active?).and_return(true)
        expect(read_connection_2).to receive(:active?).and_return(true)
        pool_connection.active?.should == true
      end

      it "should fork active? to all connections and return false if one is down" do
        expect(master_connection).to receive(:active?).and_return(true)
        expect(read_connection_1).to receive(:active?).and_return(true)
        expect(read_connection_2).to receive(:active?).and_return(false)
        pool_connection.active?.should == false
      end

      it "should fork verify! to all connections" do
        expect(master_connection).to receive(:verify!).with(5)
        expect(read_connection_1).to receive(:verify!).with(5)
        expect(read_connection_2).to receive(:verify!).with(5)
        pool_connection.verify!(5)
      end
    end

    it "should fork disconnect! to all connections" do
      expect(master_connection).to receive(:disconnect!)
      expect(read_connection_1).to receive(:disconnect!)
      expect(read_connection_2).to receive(:disconnect!)
      pool_connection.disconnect!
    end
  
    it "should fork reconnect! to all connections" do
      expect(master_connection).to receive(:reconnect!)
      expect(read_connection_1).to receive(:reconnect!)
      expect(read_connection_2).to receive(:reconnect!)
      pool_connection.reconnect!
    end
    
    it "should fork reset_runtime to all connections" do
      expect(master_connection).to receive(:reset_runtime).and_return(1)
      expect(read_connection_1).to receive(:reset_runtime).and_return(2)
      expect(read_connection_2).to receive(:reset_runtime).and_return(3)
      pool_connection.reset_runtime.should == 6
    end
  end

  context "reconnection" do
    it "should proxy requests to a connection" do
      args = [:arg1, :arg2]
      block = Proc.new{}
      expect(master_connection).to receive(:select_value).with(*args, &block)
      master_connection.should_not_receive(:active?)
      master_connection.should_not_receive(:reconnect!)
      pool_connection.send(:proxy_connection_method, master_connection, :select_value, :master, *args, &block)
    end
  
    it "should try to reconnect dead connections when they become available again" do
      master_connection.stub(:select).and_raise("SQL ERROR")      # Rails 3, 4
      master_connection.stub(:select_rows).and_raise("SQL ERROR") # Rails 5
      expect(master_connection).to receive(:active?).and_return(false, false, true)
      expect(master_connection).to receive(:reconnect!)
      now = Time.now
      lambda{pool_connection.select_value("SQL")}.should raise_error("SQL ERROR")
      Time.stub(:now => now + 31)
      lambda{pool_connection.select_value("SQL")}.should raise_error("SQL ERROR")
    end
  
    it "should not try to reconnect live connections" do
      args = [:arg1, :arg2]
      block = Proc.new{}
      expect(master_connection).to receive(:select).with(*args, &block).twice.and_raise("SQL ERROR")
      expect(master_connection).to receive(:active?).and_return(true)
      master_connection.should_not_receive(:reconnect!)
      lambda{pool_connection.send(:proxy_connection_method, master_connection, :select, :read, *args, &block)}.should raise_error("SQL ERROR")
    end
  
    it "should not try to reconnect a connection during a retry" do
      args = [:arg1, :arg2]
      block = Proc.new{}
      expect(master_connection).to receive(:select).with(*args, &block).and_raise("SQL ERROR")
      master_connection.should_not_receive(:active?)
      master_connection.should_not_receive(:reconnect!)
      lambda{pool_connection.send(:proxy_connection_method, master_connection, :select, :retry, *args, &block)}.should raise_error("SQL ERROR")
    end
  
    it "should try to execute a read statement again after a connection error" do
      connection_error = ActiveRecord::ConnectionAdapters::SeamlessDatabasePoolAdapter::DatabaseConnectionError.new
      expect(pool_connection).to receive(:current_read_connection).and_return(read_connection_1)
      expect(read_connection_1).to receive(:select).with('SQL').and_raise(connection_error)
      expect(read_connection_1).to receive(:active?).and_return(true)
      pool_connection.should_not_receive(:suppress_read_connection)
      SeamlessDatabasePool.should_not_receive(:set_persistent_read_connection)
      expect(read_connection_1).to receive(:select).with('SQL').and_return(:results)
      pool_connection.send(:select, 'SQL').should == :results
    end
  
    it "should not try to execute a read statement again after a connection error if the master connection must be used" do
      expect(master_connection).to receive(:select).with('SQL').and_raise("Fail")
      pool_connection.use_master_connection do
        lambda{pool_connection.send(:select, 'SQL')}.should raise_error("Fail")
      end
    end
  
    it "should not try to execute a read statement again after a non-connection error" do
      expect(pool_connection).to receive(:current_read_connection).and_return(read_connection_1)
      expect(pool_connection).to receive(:proxy_connection_method).with(read_connection_1, :select, :read, 'SQL').and_raise("SQL Error")
      lambda{pool_connection.send(:select, 'SQL')}.should raise_error("SQL Error")
    end
  
    it "should use a different connection on a retry if the original connection could not be reconnected" do
      expect(pool_connection).to receive(:current_read_connection).and_return(read_connection_1, read_connection_2)
      expect(read_connection_1).to receive(:select).with('SQL').and_raise("Fail")
      expect(read_connection_1).to receive(:active?).and_return(false)
      expect(pool_connection).to receive(:suppress_read_connection).with(read_connection_1, 30)
      expect(SeamlessDatabasePool).to receive(:set_persistent_read_connection).with(pool_connection, read_connection_2)
      expect(read_connection_2).to receive(:select).with('SQL').and_return(:results)
      pool_connection.send(:select, 'SQL').should == :results
    end
  
    it "should keep track of read connections that can't be reconnected for a set period" do
      pool_connection.available_read_connections.should include(read_connection_1)
      pool_connection.suppress_read_connection(read_connection_1, 30)
      pool_connection.available_read_connections.should_not include(read_connection_1)
    end
  
    it "should return dead connections to the pool after the timeout has expired" do
      pool_connection.available_read_connections.should include(read_connection_1)
      pool_connection.suppress_read_connection(read_connection_1, 0.2)
      pool_connection.available_read_connections.should_not include(read_connection_1)
      sleep(0.3)
      pool_connection.available_read_connections.should include(read_connection_1)
    end
  
    it "should not return a connection to the pool until it can be reconnected" do
      pool_connection.available_read_connections.should include(read_connection_1)
      pool_connection.suppress_read_connection(read_connection_1, 0.2)
      pool_connection.available_read_connections.should_not include(read_connection_1)
      sleep(0.3)
      expect(read_connection_1).to receive(:reconnect!)
      expect(read_connection_1).to receive(:active?).and_return(false)
      pool_connection.available_read_connections.should_not include(read_connection_1)
    end
  
    it "should try all connections again if none of them can be reconnected" do
      stack = pool_connection.instance_variable_get(:@available_read_connections)
    
      available = pool_connection.available_read_connections
      available.should include(read_connection_1)
      available.should include(read_connection_2)
      available.should include(master_connection)
      stack.size.should == 1
    
      pool_connection.suppress_read_connection(read_connection_1, 30)
      available = pool_connection.available_read_connections
      available.should_not include(read_connection_1)
      available.should include(read_connection_2)
      available.should include(master_connection)
      stack.size.should == 2
    
      pool_connection.suppress_read_connection(master_connection, 30)
      available = pool_connection.available_read_connections
      available.should_not include(read_connection_1)
      available.should include(read_connection_2)
      available.should_not include(master_connection)
      stack.size.should == 3
    
      pool_connection.suppress_read_connection(read_connection_2, 30)
      available = pool_connection.available_read_connections
      available.should include(read_connection_1)
      available.should include(read_connection_2)
      available.should include(master_connection)
      stack.size.should == 1
    end
  
    it "should not try to suppress a read connection that wasn't available in the read pool" do
      stack = pool_connection.instance_variable_get(:@available_read_connections)
      stack.size.should == 1
      pool_connection.suppress_read_connection(read_connection_1, 30)
      stack.size.should == 2
      pool_connection.suppress_read_connection(read_connection_1, 30)
      stack.size.should == 2
    end
  end
end
