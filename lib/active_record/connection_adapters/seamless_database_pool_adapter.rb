module ActiveRecord
  class Base
    def self.seamless_database_pool_connection (config)
      pool_weights = {}
      
      default_config = {:pool_weight => 1}.merge(config.merge(:adapter => config[:pool_adapter]))
      default_config.delete(:master)
      default_config.delete(:read_pool)
      default_config.delete(:pool_adapter)
      
      master_config = default_config.merge(config[:master].symbolize_keys)
      establish_adapter(master_config[:adapter])
      master_connection = send("#{master_config[:adapter]}_connection".to_sym, master_config)
      master_connection.class.send(:include, SeamlessDatabasePool::ConnectTimeout) unless master_connection.class.include?(SeamlessDatabasePool::ConnectTimeout)
      master_connection.connect_timeout = master_config[:connect_timeout]
      pool_weights[master_connection] = master_config[:pool_weight].to_i if master_config[:pool_weight].to_i > 0
      
      read_connections = []
      config[:read_pool].each do |read_config|
        read_config = default_config.merge(read_config.symbolize_keys)
        read_config[:pool_weight] = read_config[:pool_weight].to_i
        if read_config[:pool_weight] > 0
          establish_adapter(read_config[:adapter])
          conn = send("#{read_config[:adapter]}_connection".to_sym, read_config)
          conn.class.send(:include, SeamlessDatabasePool::ConnectTimeout) unless conn.class.include?(SeamlessDatabasePool::ConnectTimeout)
          conn.connect_timeout = read_config[:connect_timeout]
          read_connections << conn
          pool_weights[conn] = read_config[:pool_weight]
        end
      end if config[:read_pool]
      
      @seamless_database_pool_classes ||= {}
      klass = @seamless_database_pool_classes[master_connection.class]
      unless klass
        klass = ActiveRecord::ConnectionAdapters::SeamlessDatabasePoolAdapter.adapter_class(master_connection)
        @seamless_database_pool_classes[master_connection.class] = klass
      end
      
      return klass.new(nil, logger, master_connection, read_connections, pool_weights)
    end
    
    def self.establish_adapter (adapter)
      unless adapter then raise AdapterNotSpecified, "database configuration does not specify adapter" end
      raise AdapterNotFound, "database pool must specify adapters" if adapter == 'seamless_database_pool'
      
      begin
        require 'rubygems'
        gem "activerecord-#{adapter}-adapter"
        require "active_record/connection_adapters/#{adapter}_adapter"
      rescue LoadError
        begin
          require "active_record/connection_adapters/#{adapter}_adapter"
        rescue LoadError
          raise "Please install the #{adapter} adapter: `gem install activerecord-#{adapter}-adapter` (#{$!})"
        end
      end

      adapter_method = "#{adapter}_connection"
      if !respond_to?(adapter_method)
        raise AdapterNotFound, "database configuration specifies nonexistent #{adapter} adapter"
      end
    end

    # Force reload to use the master connection since it's probably being called for a reason.
    def reload_with_seamless_database_pool (options = nil)
      SeamlessDatabasePool.use_master_connection do
        reload_without_seamless_database_pool(options)
      end
    end
    alias_method_chain(:reload, :seamless_database_pool)
  end

  module ConnectionAdapters
    class SeamlessDatabasePoolAdapter < AbstractAdapter
      
      attr_reader :read_connections, :master_connection
      
      # Create an anonymous class that extends this one and proxies methods to the pool connections.
      def self.adapter_class (master_connection)
        # Define methods to proxy to the appropriate pool
        read_only_methods = [:select_one, :select_all, :select_value, :select_values, :select_rows]
        master_methods = master_connection.public_methods(false) + master_connection.protected_methods(false) + master_connection.private_methods(false)
        master_methods -= public_instance_methods(false) + protected_instance_methods(false) + private_instance_methods(false)
        master_methods = master_methods.collect{|m| m.to_sym}
        master_methods -= read_only_methods
        master_methods.delete(:transaction)

        klass = Class.new(self)
        master_methods.each do |method_name|
          klass.class_eval(%Q(
            def #{method_name}(*args, &block)
              begin
                proxy_connection_method(master_connection, :#{method_name}, :master, *args, &block)
              rescue DatabaseConnectionError => e
                raise e.wrapped_exception
              end
            end
          ))
        end
        
        return klass
      end
      
      def initialize (connection, logger, master_connection, read_connections, pool_weights)
        super(connection, logger)
        
        @master_connection = master_connection
        @read_connections = read_connections.dup.freeze
        
        @weighted_read_connections = []
        pool_weights.each_pair do |conn, weight|
          weight.times{@weighted_read_connections << conn}
        end
        @available_read_connections = [AvailableConnections.new(@weighted_read_connections)]
      end
      
      def adapter_name #:nodoc:
        'Seamless Database Pool'
      end
      
      # Returns an array of the master connection and the read pool connections
      def all_connections
        [@master_connection] + @read_connections
      end
      
      # Get the pool weight of a connection
      def pool_weight (connection)
        return @weighted_read_connections.select{|conn| conn == connection}.size
      end
      
      def requires_reloading?
        false
      end
      
      def active?
        active = true
        all_connections.each{|conn| active &= conn.active?}
        return active
      end
      
      def reconnect!
        all_connections.each{|conn| conn.reconnect!}
      end
      
      def disconnect!
        all_connections.each{|conn| conn.disconnect!}
      end
      
      def reset!
        all_connections.each{|conn| conn.reset!}
      end
      
      def verify!(*ignored)
        all_connections.each{|conn| conn.verify!(*ignored)}
      end
      
      def reset_runtime
        all_connections.inject(0.0){|total, conn| total += conn.reset_runtime}
      end
      
      # Get a random read connection from the pool. If the connection is not active, it will attempt to reconnect
      # to the database. If that fails, it will be removed from the pool for one minute.
      def random_read_connection
        weighted_read_connections = available_read_connections
        if @use_master or weighted_read_connections.empty?
          return master_connection
        else
          weighted_read_connections[rand(weighted_read_connections.length)]
        end
      end
      
      # Get the current read connection
      def current_read_connection
        return SeamlessDatabasePool.read_only_connection(self)
      end
      
      def transaction(start_db_transaction = true)
        use_master_connection do
          master_connection.transaction(start_db_transaction) do
            yield if block_given?
          end
        end
      end

      # Returns the last auto-generated ID from the affected table.
      def insert(sql, name = nil, pk = nil, id_value = nil, sequence_name = nil)
        master_connection.insert(sql, name, pk, id_value, sequence_name)
      end

      # Executes the update statement and returns the number of rows affected.
      def update(sql, name = nil)
        master_connection.update(sql, name)
      end

      # Executes the delete statement and returns the number of rows affected.
      def delete(sql, name = nil)
        master_connection.delete(sql, name)
      end
      
      def execute (*args)
        proxy_connection_method(current_read_connection, :execute, :read, *args)
      end
      
      def select_rows(*args)
        proxy_connection_method(current_read_connection, :select_rows, :read, *args)
      end
      
      def using_master_connection?
        !!@use_master
      end
      
      # Force using the master connection in a block.
      def use_master_connection
        save_val = @use_master
        begin
          @use_master = true
          yield if block_given?
        ensure
          @use_master = save_val
        end
      end
      
      class DatabaseConnectionError < StandardError
        attr_accessor :wrapped_exception
      end
      
      # This simple class puts an expire time on an array of connections. It is used so the a connection
      # to a down database won't try to reconnect over and over.
      class AvailableConnections
        attr_reader :connections, :failed_connection
        attr_writer :expires
        
        def initialize (connections, failed_connection = nil, expires = nil)
          @connections = connections
          @failed_connection = failed_connection
          @expires = expires
        end
        
        def expired?
          @expires < Time.now if @expires
        end
        
        def reconnect!
          failed_connection.reconnect!
          raise DatabaseConnectionError.new unless failed_connection.active?
        end
      end
      
      # Get the available weighted connections. When a connection is dead and cannot be reconnected, it will
      # be temporarily removed from the read pool so we don't keep trying to reconnect to a database that isn't
      # listening.
      def available_read_connections
        available = @available_read_connections.last
        if available.expired?
          begin
            available.reconnect!
          rescue
            # Couldn't reconnect so try again in a little bit
            available.expires = 30.seconds.from_now
            return available.connections
          end
          @available_read_connections.pop
          return available_read_connections
        else
          return available.connections
        end
      end
      
      # Temporarily remove a connection from the read pool.
      def suppress_read_connection (conn, expire)
        available = available_read_connections
        connections = available.reject{|c| c == conn}
        
        # This wasn't a read connection so don't suppress it
        return if connections.length == available.length
        
        if connections.empty?
          # No connections available so we might as well try them all again
          @available_read_connections.slice!(1, @available_read_connections.length)
        else
          # Available connections will now not include the suppressed connection for a while
          @available_read_connections.push(AvailableConnections.new(connections, conn, expire.seconds.from_now))
        end
      end
      
      protected
      
      def select (*args)
        connection = current_read_connection
        begin
          proxy_connection_method(connection, :select, :read, *args)
        rescue DatabaseConnectionError => e
          unless using_master_connection?
            # Try again with a different connection if needed unless it could have a side effect
            unless connection.active?
              suppress_read_connection(connection, 30)
              connection = current_read_connection
              SeamlessDatabasePool.set_persistent_read_connection(self, connection)
            end
            proxy_connection_method(connection, :select, :retry, *args)
          else
            raise e.wrapped_exception
          end
        end
      end
      
      private
      
      def proxy_connection_method (connection, method, proxy_type, *args, &block)
        begin
          connection.send(method, *args, &block)
        rescue => e
          unless proxy_type == :retry or connection.active?
            connection.reconnect! rescue nil
            connection_error = DatabaseConnectionError.new
            connection_error.wrapped_exception = e
            raise connection_error
          end
          raise e
        end
      end
      
    end
  end
end
