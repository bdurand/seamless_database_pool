module ActiveRecord
  class Base
    def self.read_only_connection (config)
      real_adapter = config.delete("real_adapter")
      connection = send("#{real_adapter}_connection", config.merge("adapter" => real_adapter))
      ConnectionAdapters::ReadOnlyAdapter.new(connection)
    end
  end
  
  module ConnectionAdapters
    class ReadOnlyAdapter < AbstractAdapter
      %w(select_one select_all select_value select_values select select_rows execute tables columns).each do |read_method|
        class_eval <<-EOS
          def #{read_method} (*args, &block)
            raise "Not Connected" unless @connected
            result = @connection.send(:#{read_method}, *args, &block)
            def result.read_only?
              true
            end
            result
          end
        EOS
        
        %w(update insert delete reload create_table drop_table add_index remove_index transaction).each do |write_method|
          class_eval <<-EOS
            def #{write_method} (*args, &block)
              raise NotImplementedError.new("Master method '#{write_method}' called on read only connection")
            end
          EOS
        end
      end
    
      def initialize (connection)
        @connection = connection
        @connected = true
      end
    
      def reconnect!
        @connected = true
      end
    
      def disconnect!
        @connected = false
      end
      
      def active?
        @connected
      end
    end
  end
end
