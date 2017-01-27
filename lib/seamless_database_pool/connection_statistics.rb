module SeamlessDatabasePool
  # This module is included for testing. Mix it into each of your database pool connections
  # and it will keep track of how often each connection calls update, insert, execute,
  # or select.
  module ConnectionStatistics
    def self.included(base)
      base.alias_method_chain(:update, :connection_statistics)
      base.alias_method_chain(:insert, :connection_statistics)
      base.alias_method_chain(:execute, :connection_statistics)
      base.alias_method_chain(:select, :connection_statistics)
    end

    # Get the connection statistics
    def connection_statistics
      @connection_statistics ||= {}
    end

    def reset_connection_statistics
      @connection_statistics = {}
    end

    def update_with_connection_statistics(sql, name = nil)
      increment_connection_statistic(:update) do
        update_without_connection_statistics(sql, name)
      end
    end

    def insert_with_connection_statistics(sql, name = nil)
      increment_connection_statistic(:insert) do
        insert_without_connection_statistics(sql, name)
      end
    end

    def execute_with_connection_statistics(sql, name = nil)
      increment_connection_statistic(:execute) do
        execute_without_connection_statistics(sql, name)
      end
    end

    protected

    def select_with_connection_statistics(sql, name = nil, *args)
      increment_connection_statistic(:select) do
        select_without_connection_statistics(sql, name, *args)
      end
    end

    def increment_connection_statistic(method)
      if @counting_pool_statistics
        yield
      else
        begin
          @counting_pool_statistics = true
          stat = connection_statistics[method] || 0
          @connection_statistics[method] = stat + 1
          yield
        ensure
          @counting_pool_statistics = false
        end
      end
    end
  end
end
