require 'spec_helper'

describe SeamlessDatabasePool::ConnectionStatistics do
  
  module SeamlessDatabasePool
    class ConnectionStatisticsTester
      def insert (sql, name = nil)
        "INSERT #{sql}/#{name}"
      end
      
      def update (sql, name = nil)
        execute(sql)
        "UPDATE #{sql}/#{name}"
      end
      
      def execute (sql, name = nil)
        "EXECUTE #{sql}/#{name}"
      end
      
      protected
      
      def select (sql, name = nil)
        "SELECT #{sql}/#{name}"
      end
      
      include ::SeamlessDatabasePool::ConnectionStatistics
    end
  end
  
  it "should increment statistics on update" do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    connection.update('SQL', 'name').should == "UPDATE SQL/name"
    connection.connection_statistics.should == {:update => 1}
    connection.update('SQL 2').should == "UPDATE SQL 2/"
    connection.connection_statistics.should == {:update => 2}
  end
  
  it "should increment statistics on insert" do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    connection.insert('SQL', 'name').should == "INSERT SQL/name"
    connection.connection_statistics.should == {:insert => 1}
    connection.insert('SQL 2').should == "INSERT SQL 2/"
    connection.connection_statistics.should == {:insert => 2}
  end
  
  it "should increment statistics on execute" do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    connection.execute('SQL', 'name').should == "EXECUTE SQL/name"
    connection.connection_statistics.should == {:execute => 1}
    connection.execute('SQL 2').should == "EXECUTE SQL 2/"
    connection.connection_statistics.should == {:execute => 2}
  end
  
  it "should increment statistics on select" do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    connection.send(:select, 'SQL', 'name').should == "SELECT SQL/name"
    connection.connection_statistics.should == {:select => 1}
    connection.send(:select, 'SQL 2').should == "SELECT SQL 2/"
    connection.connection_statistics.should == {:select => 2}
  end
  
  it "should increment counts only once within a block" do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    connection.should_receive(:execute).with('SQL')
    connection.update('SQL')
    connection.connection_statistics.should == {:update => 1}
  end
  
  it "should be able to clear the statistics" do
    connection = SeamlessDatabasePool::ConnectionStatisticsTester.new
    connection.update('SQL')
    connection.connection_statistics.should == {:update => 1}
    connection.reset_connection_statistics
    connection.connection_statistics.should == {}
  end
  
end
