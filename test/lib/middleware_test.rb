require "test_helper"

module Sidekiq
  module ExpectedFailures
    describe "Middleware" do
      before do
        Sidekiq.redis = REDIS
        Sidekiq.redis { |c| c.flushdb }
        Timecop.freeze(Time.local(2013, 1, 10))
        Sidekiq.expected_failures = nil
      end

      after { Timecop.return }

      let(:msg)    { {'class' => 'RandomStuff', 'args' => ['custom_argument'], 'retry' => false} }
      let(:handler){ Sidekiq::ExpectedFailures::Middleware.new }

      it 'does not handle exception by default' do
        assert_raises RuntimeError do
          handler.call(RegularWorker.new, msg, 'default') do
            raise "Whooo, hold on there!"
          end
        end
      end

      it 'can can be configured to handle exceptions by default' do
        Sidekiq.expected_failures =  { VeryOwn::CustomException => nil }

        handler.call(RegularWorker.new, msg, 'default') do
          raise VeryOwn::CustomException
        end

        assert_raises RuntimeError do
          handler.call(RegularWorker.new, msg, 'default') do
            raise "This is not handled by default"
          end
        end
      end

      it 'respects build-in rescue and ensure blocks' do
        invokes = 0
        assert_equal 0, invokes

        handler.call(SingleExceptionWorker.new, msg, 'default') do
          begin
          raise ZeroDivisionError.new("We go a problem, sir")
          rescue ZeroDivisionError => e
             invokes += 1
             raise e # and now this should be caught by middleware
          ensure
            invokes += 1
          end
        end

        assert_equal 2, invokes
      end

      it 'handles all specified exceptions' do
        handler.call(MultipleExceptionWorker.new, msg, 'default') do
          raise NotImplementedError
        end

        handler.call(MultipleExceptionWorker.new, msg, 'default') do
          raise VeryOwn::CustomException
        end
      end

      it 'logs exceptions' do
        handler.call(SingleExceptionWorker.new, msg, 'default') do
          raise ZeroDivisionError
        end

        assert_equal(['2013-01-10'], redis("smembers", "expected:dates"))
        assert_match(/custom_argument/, redis("lrange", "expected:2013-01-10", 0, -1)[0])
      end

      it 'increments own counters per exception class' do
        2.times do
          handler.call(MultipleExceptionWorker.new, msg, 'default') do
            raise VeryOwn::CustomException
          end
        end

        5.times do
          handler.call(SingleExceptionWorker.new, msg, 'default') do
            raise ZeroDivisionError
          end
        end

        assert_equal 2, redis("hget", "expected:count", "VeryOwn::CustomException").to_i
        assert_equal 5, redis("hget", "expected:count", "ZeroDivisionError").to_i
      end

      it 'logs multiple exceptions' do
        make_some_noise = lambda do |x|
          x.times do
            handler.call(SingleExceptionWorker.new, msg, 'default') do
              raise ZeroDivisionError
            end
          end
        end

        make_some_noise.call(10)

        Timecop.freeze(Time.local(2013, 5, 15))
        make_some_noise.call(5)

        assert_equal 10, redis("llen", "expected:2013-01-10")
        assert_equal 5, redis("llen", "expected:2013-05-15")
        assert_equal(['2013-05-15', '2013-01-10'].sort, redis("smembers", "expected:dates").sort)
      end

      describe 'exception notify' do

        it 'can be configured to notify once' do
          exception = ZeroDivisionError.new
          handler.expects(:handle_exception).with(exception, msg).once.returns(true)

          50.times do
            handler.call(CustomizedWorker.new, msg, 'default') do
              raise exception
            end
          end
        end

        it 'can be configured to notify multiple number of times' do
          handler.expects(:handle_exception).times(3).returns(true)

          60.times do
            handler.call(CustomizedWorker.new, msg, 'default') do
              raise VeryOwn::CustomException
            end
          end
        end

        it 'can be configured not to notify at all' do
          handler.expects(:handle_exception).never

          60.times do
            handler.call(CustomizedWorker.new, msg, 'default') do
              raise NotImplementedError
            end
          end
        end
      end
    end
  end
end
