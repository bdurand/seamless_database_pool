## 1.0.20

* Remove calls to `alias_method_chain` for Rails 5.1 compatibility (thanks yukideluxe & wjordan)

* Don't check read only connections on calls to `verify!` and `active?` when not necessary (thanks wjordan)

## 1.0.19

* Require ruby 2.0 or greater

* Eliminate deprecation warning on Rails 5 (thanks wjordan)

## 1.0.18

* ActiveRecord 5.0 compatibility (thanks jkowens)

* End support for ActiveRecord 3.1

## 1.0.17

* Do not update the HTTP session if there are no changes.

## 1.0.16

* Use shorter to_s output for output on connection.inspect.

## 1.0.15

* Implement less wordy connection to string method so logs don't fill up with long messages on connection errors.

* Update specs to remove deprecation warnings

* Fix adapter specs to work with ActiveRecord 4.1 configuration changes

## 1.0.14

* Remove custom connection timeout logic; Use the underlying driver's timeouts instead.

* Fix to work with query cache.

* Make driver less aggressive about overriding methods to proxy to the master connection.

* End support for ActiveRecord 2.x

* Add support for ActiveRecord 4.0

## 1.0.13

* Fix to work with `rake db:*` Rails tasks by removing the adapter from the configuration when db:* tasks are run.

* Fix connection pool issues so checkout/checkins don't interact with the underlying connections (thanks afex)

* Ruby 2.0/Rails 4.0 compatibility (thanks t27duck)

## 1.0.12

* Remove excessively long log messages on reconnect attempts.

## 1.0.11

* Remove debug code that prevented recovering from errors.

## 1.0.10

* Compatibility with ActiveRecord 3.1.0

## 1.0.9

* Compatibility with bind variables.

## 1.0.8

* Compatibility with ActiveRecord 3.1.0rc4

## 1.0.7

* Make compatible with ActionController 3.0

* Improved handling of down slave instances.

## 1.0.6

* Make compatible with ActiveRecord 3.0.

* Make compatible with database adapters other than MySQL including PostgrSQL.

* Better test suite to actually hit three different database adapters.

## 1.0.5

* Update docs.

* Remove rake dependency on rspec
