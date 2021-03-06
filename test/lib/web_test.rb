require "test_helper"

module Sidekiq
  describe "WebExtension" do
    include Rack::Test::Methods

    def app
      Sidekiq::Web
    end

    def create_sample_counter
      redis("hset", "expected:count", "StandardError", 5)
      redis("hset", "expected:count", "Custom::Error", 10)
    end

    def create_sample_failure
      data = {
        failed_at: Time.now.strftime("%Y/%m/%d %H:%M:%S %Z"),
        args:      [{"hash" => "options", "more" => "options"}, 123],
        exception: "ArgumentError",
        error:     "Some error message",
        worker:    "HardWorker",
        queue:     "api_calls"
      }

      Sidekiq.redis do |c|
        c.lpush("expected:2013-09-10", Sidekiq.dump_json(data))
        c.sadd("expected:dates", "2013-09-10")
      end

      Sidekiq.redis do |c|
        c.lpush("expected:2013-09-09", Sidekiq.dump_json(data))
        c.sadd("expected:dates", "2013-09-09")
      end
    end

    before do
      Sidekiq.redis = REDIS
      Sidekiq.redis {|c| c.flushdb }
      Timecop.freeze(Time.local(2013, 9, 10))
    end

    after { Timecop.return }

    it 'can display home with expected failures link' do
      get '/'
      last_response.status.must_equal(200)
      last_response.body.must_include('<a href="/expected_failures">Expected Failures</a>')
    end

    it 'can display failures page without any failures' do
      get '/expected_failures'
      last_response.status.must_equal(200)
      last_response.body.must_match(/Expected Failures/)
      last_response.body.must_match(/No failed jobs found/)
    end

    describe 'when there are failures' do
      before do
        create_sample_failure
        get '/expected_failures'
      end

      it 'should be successful' do
        last_response.status.must_equal(200)
      end

      it 'lists failed jobs' do
        last_response.body.must_match(/HardWorker/)
        last_response.body.must_match(/api_calls/)
      end

      it 'can remove all failed jobs' do
        get '/expected_failures'
        last_response.body.must_match(/HardWorker/)

        post '/expected_failures/clear', { what: 'all' }
        last_response.status.must_equal(302)
        last_response.location.must_match(/expected_failures$/)

        get '/expected_failures'
        last_response.body.must_match(/No failed jobs found/)
      end

      it 'can remove failed jobs older than 1 day' do
        get '/expected_failures'
        last_response.body.must_match(/2013-09-10/)
        last_response.body.must_match(/2013-09-09/)

        post '/expected_failures/clear', { what: 'old' }
        last_response.status.must_equal(302)
        last_response.location.must_match(/expected_failures$/)

        get '/expected_failures'
        last_response.body.wont_match(/2013-09-09/)
        last_response.body.must_match(/2013-09-10/)

        assert_nil redis("get", "expected:2013-09-09")
      end
    end

    describe 'counter' do
      describe 'when empty' do
        it 'does not display counter div' do
          create_sample_failure
          get '/expected_failures'
          last_response.body.wont_include('<dl class="dl-horizontal')
          last_response.body.wont_match(/All counters/i)
        end
      end

      describe 'when not empty' do
        before { create_sample_counter }

        it 'displays counters' do
          get '/expected_failures'
          last_response.body.must_include('<dl class="dl-horizontal')
          last_response.body.must_match(/All counters/i)
        end

        it 'can clear counters' do
          get '/expected_failures'
          last_response.body.must_match(/Custom::Error/)

          post '/expected_failures/clear', { what: 'counters' }
          last_response.status.must_equal(302)
          last_response.location.must_match(/expected_failures$/)

          get '/expected_failures'
          last_response.body.wont_match(/Custom::Error/)

          assert_nil redis("get", "expected:count")
        end
      end
    end

    describe 'stats' do
      describe 'when there are no errors' do
        before do
          get '/expected_failures/stats'
          @response = Sidekiq.load_json(last_response.body)
        end

        it 'can return failures json without any failures' do
          last_response.status.must_equal(200)
          assert_equal({}, @response['failures'])
        end
      end

      describe 'when there are errors' do
        before do
          create_sample_counter
          get '/expected_failures/stats'
          @response = Sidekiq.load_json(last_response.body)
        end

        it 'can return json with failures' do
          last_response.status.must_equal(200)
          assert_equal "5", @response['failures']['StandardError']
          assert_equal "10", @response['failures']['Custom::Error']
        end
      end
    end

    describe 'pagination & filtering' do
      before do
        51.times { create_sample_failure }
      end

      it 'displays pagination widget when needed' do
        get '/expected_failures'
        last_response.body.must_include('<ul class="pagination')
      end

      it 'properly links to next page' do
        get '/expected_failures/day/2013-09-10'
        last_response.body.must_include('/expected_failures/day/2013-09-10?page=2')
      end
    end
  end
end
