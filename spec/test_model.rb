module SeamlessDatabasePool
  class TestModel < ActiveRecord::Base
    self.abstract_class = true
    
    class << self
      def database_configs
        adapters = ENV['TEST_ADAPTERS'].blank? ? [] : ENV['TEST_ADAPTERS'].split(/\s+/)
        configs = {}
        YAML.load_file(File.expand_path("../database.yml", __FILE__)).each do |adapter_name, adapter_config|
          configs[adapter_name] = adapter_config if adapters.include?(adapter_name.downcase)
        end
        configs
      end
      
      def use_database_connection(db_name)
        establish_connection(database_configs[db_name.to_s])
      end
      
      def db_model(db_name)
        model_class_name = "#{db_name.classify}TestModel"
        unless const_defined?(model_class_name)
          klass = Class.new(self)
          const_set(model_class_name, klass)
          klass = const_get(model_class_name)
          klass.use_database_connection(db_name)
        end
        const_get(model_class_name)
      end
      
      def create_tables
        connection.create_table(table_name) do |t|
          t.column :name, :string
          t.column :value, :integer
        end unless table_exists?
        connection.clear_cache! if connection.respond_to?(:clear_cache!)
        undefine_attribute_methods if respond_to?(:undefine_attribute_methods)
      end
 
      def drop_tables
        connection.drop_table(table_name)
        connection.clear_cache! if connection.respond_to?(:clear_cache!)
        undefine_attribute_methods if respond_to?(:undefine_attribute_methods)
      end
      
      def cleanup_database!
        connection.disconnect!
        sqlite3_config = database_configs['sqlite3']
        if sqlite3_config && File.exist?(sqlite3_config['database'])
          File.delete(sqlite3_config['database'])
        end
      end
    end
  end
end
