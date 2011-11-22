require 'spec_helper'
require 'active_record/connection_adapters/read_only_adapter'

describe "Test connection adapters" do
  if SeamlessDatabasePool::TestModel.database_configs.empty?
    puts "No adapters specified for testing. Specify the adapters with TEST_ADAPTERS variable"
  else
    SeamlessDatabasePool::TestModel.database_configs.keys.each do |adapter|
      context adapter do
        let(:model){ SeamlessDatabasePool::TestModel.db_model(adapter) }
        let(:connection){ model.connection }
        let(:read_connection){ connection.available_read_connections.first }
        let(:master_connection){ connection.master_connection }
  
        before(:all) do
          ActiveRecord::Base.establish_connection('adapter' => "sqlite3", 'database' => ":memory:")
          model.use_database_connection(adapter)
          model.create_tables
        end
  
        after(:all) do
          model.drop_tables
          model.cleanup_database!
        end
  
        before(:each) do
          model.create!(:name => 'test', :value => 1)
          SeamlessDatabasePool.use_persistent_read_connection
        end
  
        after(:each) do
          model.delete_all
          SeamlessDatabasePool.use_master_connection
        end
  
        it "should force the master connection on reload" do
          record = model.first
          SeamlessDatabasePool.should_not_receive(:current_read_connection)
          record.reload
        end
      
        it "should quote table names properly" do
          connection.quote_table_name("foo").should == master_connection.quote_table_name("foo")
        end
              
        it "should quote column names properly" do
          connection.quote_column_name("foo").should == master_connection.quote_column_name("foo")
        end
              
        it "should quote string properly" do
          connection.quote_string("foo").should == master_connection.quote_string("foo")
        end
              
        it "should quote booleans properly" do
          connection.quoted_true.should == master_connection.quoted_true
          connection.quoted_false.should == master_connection.quoted_false
        end
              
        it "should quote dates properly" do
          date = Date.today
          time = Time.now
          connection.quoted_date(date).should == master_connection.quoted_date(date)
          connection.quoted_date(time).should == master_connection.quoted_date(time)
        end
          
        it "should query for records" do
          record = model.find_by_name("test")
          record.name.should == "test"
        end
          
        it "should work with query caching" do
          record_id =  model.first.id
          model.cache do
            found = model.find(record_id)
            found.name = "new value"
            found.save!
            model.find(record_id).name.should == "new value"
          end
        end
          
        context "read connection" do
          let(:sample_sql){"SELECT #{connection.quote_column_name('name')} FROM #{connection.quote_table_name(model.table_name)}"}
            
          it "should not include the master connection in the read pool for these tests" do
            connection.available_read_connections.should_not include(master_connection)
            connection.current_read_connection.should_not == master_connection
          end
            
          it "should send select to the read connection" do
            results = connection.send(:select, sample_sql)
            results.should == [{"name" => "test"}]
            results.should == master_connection.send(:select, sample_sql)
            results.should be_read_only
          end
          
          it "should send select_all to the read connection" do
            results = connection.select_all(sample_sql)
            results.should == [{"name" => "test"}]
            results.should == master_connection.select_all(sample_sql)
            results.should be_read_only
          end
          
          it "should send select_one to the read connection" do
            results = connection.select_one(sample_sql)
            results.should == {"name" => "test"}
            results.should == master_connection.select_one(sample_sql)
            results.should be_read_only
          end
          
          it "should send select_values to the read connection" do
            results = connection.select_values(sample_sql)
            results.should == ["test"]
            results.should == master_connection.select_values(sample_sql)
            results.should be_read_only
          end
          
          it "should send select_value to the read connection" do
            results = connection.select_value(sample_sql)
            results.should == "test"
            results.should == master_connection.select_value(sample_sql)
            results.should be_read_only
          end
          
          it "should send select_rows to the read connection" do
            results = connection.select_all(sample_sql)
            results.should == [{"name" => "test"}]
            results.should == master_connection.select_all(sample_sql)
            results.should be_read_only
          end
          
          it "should send execute to the read connection" do
            results = connection.execute(sample_sql)
            results.should be_read_only
          end
          
          it "should send columns to the read connection" do
            results = connection.columns(model.table_name)
            columns = results.collect{|c| c.name}.sort.should
            columns.should == ["id", "name", "value"]
            columns.should == master_connection.columns(model.table_name).collect{|c| c.name}.sort
            results.should be_read_only
          end
          
          it "should send tables to the read connection" do
            results = connection.tables
            results.should == ["test_models"]
            results.should == master_connection.tables
            results.should be_read_only
          end
        
          it "should reconnect dead connections in the read pool" do
            read_connection.disconnect!
            read_connection.should_not be_active
            results = connection.select_all(sample_sql)
            results.should be_read_only
            read_connection.should be_active
          end
        end
          
        context "master connection" do
          let(:insert_sql){ "INSERT INTO #{connection.quote_table_name(model.table_name)} (#{connection.quote_column_name('name')}) VALUES ('new')" }
          let(:update_sql){ "UPDATE #{connection.quote_table_name(model.table_name)} SET #{connection.quote_column_name('value')} = 2" }
          let(:delete_sql){ "DELETE FROM #{connection.quote_table_name(model.table_name)}" }
            
          it "should blow up if a master connection method is sent to the read only connection" do
            lambda{read_connection.update(update_sql)}.should raise_error(NotImplementedError)
            lambda{read_connection.update(insert_sql)}.should raise_error(NotImplementedError)
            lambda{read_connection.update(delete_sql)}.should raise_error(NotImplementedError)
            lambda{read_connection.transaction{}}.should raise_error(NotImplementedError)
            lambda{read_connection.create_table(:test)}.should raise_error(NotImplementedError)
          end
            
          it "should send update to the master connection" do
            connection.update(update_sql)
            model.first.value.should == 2
          end
          
          it "should send insert to the master connection" do
            connection.update(insert_sql)
            model.find_by_name("new").should_not == nil
          end
          
          it "should send delete to the master connection" do
            connection.update(delete_sql)
            model.first.should == nil
          end
          
          it "should send transaction to the master connection" do
            connection.transaction do
              connection.update(update_sql)
            end
            model.first.value.should == 2
          end
          
          it "should send schema altering statements to the master connection" do
            SeamlessDatabasePool.use_master_connection do
              begin
                connection.create_table(:foo) do |t|
                  t.string :name
                end
                connection.add_index(:foo, :name)
              ensure
                connection.remove_index(:foo, :name)
                connection.drop_table(:foo)
              end
            end
          end
          
          it "should properly dump the schema" do
            schema = <<-EOS
              ActiveRecord::Schema.define(:version => 0) do
                create_table "test_models", :force => true do |t|
                  t.string  "name"
                  t.integer "value"
                end
              end
            EOS
            schema = schema.gsub(/^ +/, '').gsub(/ +/, ' ').strip
            
            io = StringIO.new
            ActiveRecord::SchemaDumper.dump(connection, io)
            generated_schema = io.string.gsub(/^#.*$/, '').gsub(/\n+/, "\n").gsub(/^ +/, '').gsub(/ +/, ' ').strip
            generated_schema.should == schema
          end
        end
      end
    end
  end
end
