module SeamlessDatabasePool
  class Test < ActiveRecord::Base
    def self.create_tables
      db_dir = File.expand_path(File.join(__FILE__, '..', 'tmp'))
      Dir.mkdir(db_dir) unless File.exist?(db_dir)
      db = File.join(db_dir, 'test_SeamlessDatabasePool.sqlite3')
      establish_connection("adapter" => "sqlite3", "database" => db)
      
      connection.create_table(Thing.table_name) do |t|
        t.column :name, :string
        t.column :model_id, :integer
      end unless Thing.table_exists?
      
      connection.create_table(Model.table_name) do |t|
        t.column :name, :string
      end unless Model.table_exists?
    end
 
    def self.drop_tables
      db_dir = File.expand_path(File.join(__FILE__, '..', 'tmp'))
      db = File.join(db_dir, 'test_SeamlessDatabasePool.sqlite3')
      connection.disconnect!
      File.delete(db) if File.exist?(db)
      Dir.delete(db_dir) if File.exist?(db_dir) and Dir.entries(db_dir).reject{|f| f.match(/^\.+$/)}.empty?
    end
    
    class Thing < Test
      belongs_to :model, :class_name => "SeamlessDatabasePool::Test::Model"
    end
    
    class Model < Test
      has_many :things, :class_name => "SeamlessDatabasePool::Test::Thing"
    end
  end
end
