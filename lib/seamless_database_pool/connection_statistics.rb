module SeamlessDatabasePool
  # This module is included for testing. Mix it into each of your database pool connections
  # and it will keep track of how often each connection calls update, insert, execute,
  # or select.
  module ConnectionStatistics
    # Get the connection statistics
    def connection_statistics
      @connection_statistics ||= {}
    end

    def reset_connection_statistics
      @connection_statistics = {}
    end

    def update(sql, name = nil)
      increment_connection_statistic(:update) do
        super(sql, name)
      end
    end

    def insert(sql, name = nil)
      increment_connection_statistic(:insert) do
        super(sql, name)
      end
    end

    def execute(sql, name = nil)
      increment_connection_statistic(:execute) do
        super(sql, name)
      end
    end

    protected

    def select(sql, name = nil, *args)
      increment_connection_statistic(:select) do
        super(sql, name, *args)
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
