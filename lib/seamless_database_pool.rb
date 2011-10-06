require File.join(File.dirname(__FILE__), 'seamless_database_pool', 'connect_timeout.rb')
require File.join(File.dirname(__FILE__), 'seamless_database_pool', 'connection_statistics.rb')
require File.join(File.dirname(__FILE__), 'seamless_database_pool', 'controller_filter.rb')
require File.join(File.dirname(__FILE__), 'active_record', 'connection_adapters', 'seamless_database_pool_adapter.rb')
$LOAD_PATH << File.dirname(__FILE__) unless $LOAD_PATH.include?(File.dirname(__FILE__))

# This module allows setting the read pool connection type. Generally you will use one of
#
#   - use_random_read_connection
#   - use_persistent_read_connection
#   - use_master_connection
#
# Each of these methods can take an optional block. If they are called with a block, they
# will set the read connection type only within the block. Otherwise they will set the default
# read connection type. If none is ever called, the read connection type will be :master.

module SeamlessDatabasePool
    
  # Adapter name to class name map. This exists because there isn't an obvious way to translate things like
  # sqlite3 to SQLite3. The adapters that ship with ActiveRecord are defined here. If you use
  # an adapter that doesn't translate directly to camel case, then add the mapping here in an initializer.
  ADAPTER_TO_CLASS_NAME_MAP = {"sqlite" => "SQLite", "sqlite3" => "SQLite3", "postgresql" => "PostgreSQL"}
  
  READ_CONNECTION_METHODS = [:master, :persistent, :random]

  class << self
    # Call this method to use a random connection from the read pool for every select statement.
    # This method is good if your replication is very fast. Otherwise there is a chance you could
    # get inconsistent results from one request to the next. This can result in mysterious failures
    # if your code selects a value in one statement and then uses in another statement. You can wind
    # up trying to use a value from one server that hasn't been replicated to another one yet.
    # This method is best if you have few processes which generate a lot of queries and you have
    # fast replication.
    def use_random_read_connection
      if block_given?
        set_read_only_connection_type(:random){yield}
      else
        Thread.current[:read_only_connection] = :random
      end
    end
  
    # Call this method to pick a random connection from the read pool and use it for all subsequent
    # select statements. This provides consistency from one select statement to the next. This
    # method should always be called with a block otherwise you can end up with an imbalanced read
    # pool. This method is best if you have lots of processes which have a relatively few select
    # statements or a slow replication mechanism. Generally this is the best method to use for web
    # applications.
    def use_persistent_read_connection
      if block_given?
        set_read_only_connection_type(:persistent){yield}
      else
        Thread.current[:read_only_connection] = {}
      end
    end
  
    # Call this method to use the master connection for all subsequent select statements. This
    # method is most useful when you are doing lots of updates since it guarantees consistency
    # if you do a select immediately after an update or insert.
    #
    # The master connection will also be used for selects inside any transaction blocks. It will
    # also be used if you pass :readonly => false to any ActiveRecord.find method.
    def use_master_connection
      if block_given?
        set_read_only_connection_type(:master){yield}
      else
        Thread.current[:read_only_connection] = :master
      end
    end
  
    # Set the read only connection type to either :master, :random, or :persistent.
    def set_read_only_connection_type(connection_type)
      saved_connection = Thread.current[:read_only_connection]
      retval = nil
      begin
        connection_type = {} if connection_type == :persistent
        Thread.current[:read_only_connection] = connection_type
        retval = yield if block_given?
      ensure
        Thread.current[:read_only_connection] = saved_connection
      end
      return retval
    end
  
    # Get the read only connection type currently in use. Will be one of :master, :random, or :persistent.
    def read_only_connection_type(default = :master)
      connection_type = Thread.current[:read_only_connection] || default
      connection_type = :persistent if connection_type.kind_of?(Hash)
      return connection_type
    end
  
    # Get a read only connection from a connection pool.
    def read_only_connection(pool_connection)
      return pool_connection.master_connection if pool_connection.using_master_connection?
      connection_type = Thread.current[:read_only_connection]
    
      if connection_type.kind_of?(Hash)
        connection = connection_type[pool_connection]
        unless connection
          connection = pool_connection.random_read_connection
          connection_type[pool_connection] = connection
        end
        return connection
      elsif connection_type == :random
        return pool_connection.random_read_connection
      else
        return pool_connection.master_connection
      end
    end
  
    # This method is provided as a way to change the persistent connection when it fails and a new one is substituted.
    def set_persistent_read_connection(pool_connection, read_connection)
      connection_type = Thread.current[:read_only_connection]
      connection_type[pool_connection] = read_connection if connection_type.kind_of?(Hash)
    end
  
    def clear_read_only_connection
      Thread.current[:read_only_connection] = nil
    end
    
    # Get the connection adapter class for an adapter name. The class will be loaded from
    # ActiveRecord::ConnectionAdapters::NameAdapter where Name is the camelized version of the name.
    # If the adapter class does not fit this pattern (i.e. sqlite3 => SQLite3Adapter), then add
    # the mapping to the +ADAPTER_TO_CLASS_NAME_MAP+ Hash.
    def adapter_class_for(name)
      name = name.to_s
      class_name = ADAPTER_TO_CLASS_NAME_MAP[name] || name.camelize
      "ActiveRecord::ConnectionAdapters::#{class_name}Adapter".constantize
    end
  end
  
end
