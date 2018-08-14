require 'rubygems'
require 'simplecov'
require 'active_support/core_ext'
require 'factory_girl'
require 'turn'
require 'pry'
require 'database_cleaner'


require 'active_record'

ActiveRecord::Base.establish_connection(
  :adapter => "sqlite3",
  :database => "tmp/test.db",
  :verbosity => "quiet")

load File.join(File.dirname(__FILE__), "support", "schema.rb")


require 'factories/tenants'


DatabaseCleaner.strategy = :transaction

class ActiveSupport::TestCase
  setup do
    DatabaseCleaner.start
  end
  teardown do
    DatabaseCleaner.clean
  end
end

require "minitest/autorun"
