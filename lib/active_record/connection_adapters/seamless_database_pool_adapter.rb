module ActiveRecord
  class Base
    class << self
      def seamless_database_pool_connection(config)
        pool_weights = {}

        config = config.with_indifferent_access
        default_config = {:pool_weight => 1}.merge(config.merge(:adapter => config[:pool_adapter])).with_indifferent_access
        default_config.delete(:master)
        default_config.delete(:read_pool)
        default_config.delete(:pool_adapter)

        master_config = default_config.merge(config[:master]).with_indifferent_access
        establish_adapter(master_config[:adapter])
        master_connection = send("#{master_config[:adapter]}_connection".to_sym, master_config)
        master_connection.class.send(:include, SeamlessDatabasePool::ConnectTimeout) unless master_connection.class.include?(SeamlessDatabasePool::ConnectTimeout)
        master_connection.connect_timeout = master_config[:connect_timeout]
        pool_weights[master_connection] = master_config[:pool_weight].to_i if master_config[:pool_weight].to_i > 0
        
        read_connections = []
        config[:read_pool].each do |read_config|
          read_config = default_config.merge(read_config).with_indifferent_access
          read_config[:pool_weight] = read_config[:pool_weight].to_i
          if read_config[:pool_weight] > 0
            begin
              establish_adapter(read_config[:adapter])
              conn = send("#{read_config[:adapter]}_connection".to_sym, read_config)
              conn.class.send(:include, SeamlessDatabasePool::ConnectTimeout) unless conn.class.include?(SeamlessDatabasePool::ConnectTimeout)
              conn.connect_timeout = read_config[:connect_timeout]
              read_connections << conn
              pool_weights[conn] = read_config[:pool_weight]
            rescue Exception => e
              if logger
                logger.error("Error connecting to read connection #{read_config.inspect}")
                logger.error(e)
              end
            end
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

      def establish_adapter(adapter)
        raise AdapterNotSpecified.new("database configuration does not specify adapter") unless adapter
        raise AdapterNotFound.new("database pool must specify adapters") if adapter == 'seamless_database_pool'
      
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
    end
    
    module SeamlessDatabasePoolBehavior
      def self.included(base)
        base.alias_method_chain(:reload, :seamless_database_pool)
      end
      
      # Force reload to use the master connection since it's probably being called for a reason.
      def reload_with_seamless_database_pool(*args)
        SeamlessDatabasePool.use_master_connection do
          reload_without_seamless_database_pool(*args)
        end
      end
    end
    
    include(SeamlessDatabasePoolBehavior) unless include?(SeamlessDatabasePoolBehavior)
  end

  module ConnectionAdapters
    class SeamlessDatabasePoolAdapter < AbstractAdapter
      
      attr_reader :read_connections, :master_connection
      
      class << self
        # Create an anonymous class that extends this one and proxies methods to the pool connections.
        def adapter_class(master_connection)
          # Define methods to proxy to the appropriate pool
          read_only_methods = [:select_one, :select_all, :select_value, :select_values, :select, :select_rows, :execute, :tables, :columns]
          master_methods = []
          master_connection_classes = [AbstractAdapter, Quoting, DatabaseStatements, SchemaStatements]
          master_connection_classes << DatabaseLimits if const_defined?(:DatabaseLimits)
          master_connection_class = master_connection.class
          while ![Object, AbstractAdapter].include?(master_connection_class) do
            master_connection_classes << master_connection_class
            master_connection_class = master_connection_class.superclass
          end
          master_connection_classes.each do |connection_class|
            master_methods.concat(connection_class.public_instance_methods(false))
            master_methods.concat(connection_class.protected_instance_methods(false))
          end
          master_methods.uniq!
          master_methods -= public_instance_methods(false) + protected_instance_methods(false) + private_instance_methods(false)
          master_methods = master_methods.collect{|m| m.to_sym}
          master_methods -= read_only_methods

          klass = Class.new(self)
          master_methods.each do |method_name|
            klass.class_eval <<-EOS, __FILE__, __LINE__ + 1
              def #{method_name}(*args, &block)
                use_master_connection do
                  return proxy_connection_method(master_connection, :#{method_name}, :master, *args, &block)
                end
              end
            EOS
          end
        
          read_only_methods.each do |method_name|
            klass.class_eval <<-EOS, __FILE__, __LINE__ + 1
              def #{method_name}(*args, &block)
                connection = @use_master ? master_connection : current_read_connection
                proxy_connection_method(connection, :#{method_name}, :read, *args, &block)
              end
            EOS
          end
          klass.send :protected, :select
        
          return klass
        end
      
        # Set the arel visitor on the connections.
        def visitor_for(pool)
          # This is ugly, but then again, so is the code in ActiveRecord for setting the arel
          # visitor. There is a note in the code indicating the method signatures should be updated.
          config = pool.spec.config.with_indifferent_access
          adapter = config[:master][:adapter] || config[:pool_adapter]
          SeamlessDatabasePool.adapter_class_for(adapter).visitor_for(pool)
        end
      end
      
      def initialize(connection, logger, master_connection, read_connections, pool_weights)
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
        'Seamless_Database_Pool'
      end
      
      # Returns an array of the master connection and the read pool connections
      def all_connections
        [@master_connection] + @read_connections
      end
      
      # Get the pool weight of a connection
      def pool_weight(connection)
        return @weighted_read_connections.select{|conn| conn == connection}.size
      end
      
      def requires_reloading?
        false
      end
      
      def visitor=(visitor)
        all_connections.each{|conn| conn.visitor = visitor}
      end
      
      def visitor
        master_connection.visitor
      end
      
      def active?
        active = true
        do_to_connections {|conn| active &= conn.active?}
        return active
      end

      def reconnect!
        do_to_connections {|conn| conn.reconnect!}
      end

      def disconnect!
        do_to_connections {|conn| conn.disconnect!}
      end

      def reset!
        do_to_connections {|conn| conn.reset!}
      end

      def verify!(*ignored)
        do_to_connections {|conn| conn.verify!(*ignored)}
      end

      def reset_runtime
        total = 0.0
        do_to_connections {|conn| total += conn.reset_runtime}
        total
      end
      
      # Get a random read connection from the pool. If the connection is not active, it will attempt to reconnect
      # to the database. If that fails, it will be removed from the pool for one minute.
      def random_read_connection
        weighted_read_connections = available_read_connections
        if @use_master || weighted_read_connections.empty?
          return master_connection
        else
          weighted_read_connections[rand(weighted_read_connections.length)]
        end
      end
      
      # Get the current read connection
      def current_read_connection
        return SeamlessDatabasePool.read_only_connection(self)
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
      end
      
      # This simple class puts an expire time on an array of connections. It is used so the a connection
      # to a down database won't try to reconnect over and over.
      class AvailableConnections
        attr_reader :connections, :failed_connection
        attr_writer :expires
        
        def initialize(connections, failed_connection = nil, expires = nil)
          @connections = connections
          @failed_connection = failed_connection
          @expires = expires
        end
        
        def expired?
          @expires ? @expires <= Time.now : false
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
            @logger.info("Adding dead database connection back to the pool: #{available.inspect}") if @logger
            available.reconnect!
          rescue => e
            # Couldn't reconnect so try again in a little bit
            if @logger
              @logger.warn("Failed to reconnect with: #{available.inspect}")
              @logger.warn(e)
            end
            available.expires = 30.seconds.from_now
            return available.connections
          end
          
          # If reconnect is successful, the connection will have been re-added to @available_read_connections list,
          # so let's pop this old version of the connection
          @available_read_connections.pop
          
          # Now we'll try again after either expiring our bad connection or re-adding our good one
          return available_read_connections
        else
          return available.connections
        end
      end
      
      def reset_available_read_connections
        @available_read_connections.slice!(1, @available_read_connections.length)
        @available_read_connections.first.connections.each do |connection|
          unless connection.active?
            connection.reconnect! rescue nil
          end
        end
      end
      
      # Temporarily remove a connection from the read pool.
      def suppress_read_connection(conn, expire)
        available = available_read_connections
        connections = available.reject{|c| c == conn}

        # This wasn't a read connection so don't suppress it
        return if connections.length == available.length

        if connections.empty?
          @logger.warn("All read connections are marked dead; trying them all again.") if @logger
          # No connections available so we might as well try them all again
          reset_available_read_connections
        else
          @logger.warn("Removing #{conn.inspect} from the connection pool for #{expire} seconds") if @logger
          # Available connections will now not include the suppressed connection for a while
          @available_read_connections.push(AvailableConnections.new(connections, conn, expire.seconds.from_now))
        end
      end
      
      private
      
      def proxy_connection_method(connection, method, proxy_type, *args, &block)
        begin
          connection.send(method, *args, &block)
        rescue => e
          # If the statement was a read statement and it wasn't forced against the master connection
          # try to reconnect if the connection is dead and then re-run the statement.
          if proxy_type == :read && !using_master_connection?
            unless connection.active?
              suppress_read_connection(connection, 30)
              connection = current_read_connection
              SeamlessDatabasePool.set_persistent_read_connection(self, connection)
            end
            proxy_connection_method(connection, method, :retry, *args, &block)
          else
            raise e
          end
        end
      end

      # Yield a block to each connection in the pool. If the connection is dead, ignore the error
      # unless it is the master connection
      def do_to_connections
        all_connections.each do |conn|
          begin
            yield(conn)
          rescue => e
            raise e if conn == master_connection
          end
        end
      end
    end
  end
end
