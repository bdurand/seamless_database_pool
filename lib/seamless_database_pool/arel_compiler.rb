module Arel
  module SqlCompiler
    # Hook into arel to use the compiler used by the master connection.
    class Seamless_Database_PoolCompiler < GenericCompiler
      def self.new(relation)
        @compiler_classes ||= {}
        master_adapter = relation.engine.connection.master_connection.adapter_name
        compiler_class = @compiler_classes[master_adapter]
        unless compiler_class
          begin
            require "arel/engines/sql/compilers/#{master_adapter.downcase}_compiler"
          rescue LoadError
            begin
              # try to load an externally defined compiler, in case this adapter has defined the compiler on its own.
              require "#{master_adapter.downcase}/arel_compiler"
            rescue LoadError
              raise LoadError.new("#{master_adapter} is not supported by Arel.")
            end
          end
          compiler_class = Arel::SqlCompiler.const_get("#{master_adapter}Compiler")
          @compiler_classes[master_adapter] = compiler_class
        end
        compiler_class.new(relation)
      end
    end
  end
end
