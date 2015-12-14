require 'coveralls'
Coveralls.wear! do
  add_filter "/test/"
end

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

ENV['RACK_ENV'] = 'test'

require "minitest/autorun"
require "minitest/pride"

require "mocha/api"
require "timecop"
require "rack/test"

require "sidekiq"
require "sidekiq/web"

require "sidekiq-expected_failures"
require "sidekiq/expected_failures/web"

require_relative "test_workers"

Sidekiq.logger.level = Logger::ERROR

REDIS = Sidekiq::RedisConnection.create(url: "redis://localhost/15")

def redis(command, *args)
  Sidekiq.redis do |c|
    c.send(command, *args)
  end
end
