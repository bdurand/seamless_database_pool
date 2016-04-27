module SeamlessDatabasePool
  # This module provides a simple method of declaring which read pool connection type should
  # be used for various ActionController actions. To use it, you must first mix it into
  # you controller and then call use_database_pool to configure the connection types. Generally
  # you should just do this in ApplicationController and call use_database_pool in your controllers
  # when you need different connection types.
  #
  # Example:
  # 
  #   ApplicationController < ActionController::Base
  #     include SeamlessDatabasePool::ControllerFilter
  #     use_database_pool :all => :persistent, [:save, :delete] => :master
  #     ...
  
  module ControllerFilter    
    def self.included(base)
      unless base.respond_to?(:use_database_pool)
        base.extend(ClassMethods)
        base.class_eval do
          if base.method_defined?(:perform_action) || base.private_method_defined?(:perform_action)
            alias_method_chain :perform_action, :seamless_database_pool
          else
            alias_method_chain :process, :seamless_database_pool
          end
          alias_method_chain :redirect_to, :seamless_database_pool
        end
      end
    end
    
    module ClassMethods
      
      def seamless_database_pool_options
        return @seamless_database_pool_options if @seamless_database_pool_options
        @seamless_database_pool_options = superclass.seamless_database_pool_options.dup if superclass.respond_to?(:seamless_database_pool_options)
        @seamless_database_pool_options ||= {}
      end
      
      # Call this method to set up the connection types that will be used for your actions.
      # The configuration is given as a hash where the key is the action name and the value is
      # the connection type (:master, :persistent, or :random). You can specify :all as the action
      # to define a default connection type. You can also specify the action names in an array
      # to easily map multiple actions to one connection type.
      #
      # The configuration is inherited from parent controller classes, so if you have default
      # behavior, you should simply specify it in ApplicationController to have it available
      # globally.
      def use_database_pool(options)
        remapped_options = seamless_database_pool_options
        options.each_pair do |actions, connection_method|
          unless SeamlessDatabasePool::READ_CONNECTION_METHODS.include?(connection_method)
            raise "Invalid read pool method: #{connection_method}; should be one of #{SeamlessDatabasePool::READ_CONNECTION_METHODS.inspect}"
          end
          actions = [actions] unless actions.kind_of?(Array)
          actions.each do |action|
            remapped_options[action.to_sym] = connection_method
          end
        end
        @seamless_database_pool_options = remapped_options
      end
    end
    
    # Force the master connection to be used on the next request. This is very useful for the Post-Redirect pattern
    # where you post a request to your save action and then redirect the user back to the edit action. By calling
    # this method, you won't have to worry if the replication engine is slower than the redirect. Normally you
    # won't need to call this method yourself as it is automatically called when you perform a redirect from within
    # a master connection block. It is made available just in case you have special needs that don't quite fit
    # into this module's default logic.
    def use_master_db_connection_on_next_request
      session[:next_request_db_connection] = :master if session
    end
    
    def seamless_database_pool_options
      self.class.seamless_database_pool_options
    end
    
    # Rails 3.x hook for setting the read connection for the request.
    def process_with_seamless_database_pool(action, *args)
      set_read_only_connection_for_block(action) do
        process_without_seamless_database_pool(action, *args)
      end
    end
    
    def redirect_to_with_seamless_database_pool(options = {}, response_status = {})
      if SeamlessDatabasePool.read_only_connection_type(nil) == :master
        use_master_db_connection_on_next_request
      end
      redirect_to_without_seamless_database_pool(options, response_status)
    end
    
    private
    
    # Rails 2.x hook for setting the read connection for the request.
    def perform_action_with_seamless_database_pool(*args)
      set_read_only_connection_for_block(action_name) do
        perform_action_without_seamless_database_pool(*args)
      end
    end
    
    # Set the read only connection for a block. Used to set the connection for a controller action.
    def set_read_only_connection_for_block(action)
      read_pool_method = nil
      if session
        read_pool_method = session[:next_request_db_connection]
        session.delete(:next_request_db_connection) if session[:next_request_db_connection]
      end
      
      read_pool_method ||= seamless_database_pool_options[action.to_sym] || seamless_database_pool_options[:all]
      if read_pool_method
        SeamlessDatabasePool.set_read_only_connection_type(read_pool_method) do
          yield
        end
      else
        yield
      end
    end
  end
end
