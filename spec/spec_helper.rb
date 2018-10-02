require 'simplecov'
SimpleCov.start do
  add_filter "/spec/"
end

require './lib/rethinkdb'
require './spec/integration_helpers'

RSpec.configure do |config|
  config.include RethinkDB::Shortcuts
  config.include RethinkDB::IntegrationHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.define_derived_metadata(file_path: %r{spec/integration}) do |metadata|
    metadata[:integration] = true
  end

  # TODO maybe a little heavy handed?
  config.before(:each, :integration) do
    integration_setup
  end

  config.after(:each, :integration) do
    integration_teardown
  end
end
