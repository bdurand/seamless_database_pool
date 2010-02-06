module SeamlessDatabasePool
  # This module is mixed into connection adapters to allow the reconnect! method to timeout if the
  # IP address becomes unreachable. The default timeout is 1 second, but you can change it by setting
  # the connect_timeout parameter in the adapter configuration.
  module ConnectTimeout
    attr_accessor :connect_timeout
    
    def self.included (base)
      base.alias_method_chain :reconnect!, :connect_timeout
    end
    
    def reconnect_with_connect_timeout!
      begin
        timeout(connect_timeout || 1) do
          reconnect_without_connect_timeout!
        end
      rescue TimeoutError
        raise "reconnect timed out"
      end
    end
  end
end
