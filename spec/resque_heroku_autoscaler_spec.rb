require 'spec_helper'

class TestJob
  extend Resque::Plugins::HerokuAutoscaler

  @queue = :test
end

class AnotherJob
  extend Resque::Plugins::HerokuAutoscaler

  @queue = :test
end

describe Resque::Plugins::HerokuAutoscaler do
  before do
    @fake_heroku_client = Object.new
    stub(@fake_heroku_client).ps_scale
    stub(@fake_heroku_client).ps { [{'process' => 'worker'}] }
    stub(TestJob).log
    Resque::Plugins::HerokuAutoscaler::Config.reset
  end

  it "should be a valid Resque plugin" do
    lambda { Resque::Plugin.lint(Resque::Plugins::HerokuAutoscaler) }.should_not raise_error
  end

  describe ".after_enqueue_scale_workers_up" do
    it "should add the hook" do
      Resque::Plugin.after_enqueue_hooks(TestJob).should include(:after_enqueue_scale_workers_up)
    end

    it "should take whatever args Resque hands in" do
      stub(TestJob).heroku_client { @fake_heroku_client }

      lambda do
        TestJob.after_enqueue_scale_workers_up("some", "random", "aguments", 42)
      end.should_not raise_error
    end
  end

  describe ".after_perform_scale_workers" do
    before do
      Resque.redis.set('worker:last_scaled', Time.now - 120)
      stub(TestJob).heroku_client { @fake_heroku_client }
    end
    it "should add the hook" do
      Resque::Plugin.after_hooks(TestJob).should include(:after_perform_scale_workers)
    end

    it "should take whatever args Resque hands in" do
      Resque::Plugins::HerokuAutoscaler.class_eval("@@heroku_client = nil")
      stub(Heroku::Client).new { stub!.ps_scale }

      lambda { TestJob.after_perform_scale_workers("some", "random", "aguments", 42) }.should_not raise_error
    end
  end

  describe ".on_failure_scale_workers" do
    before do
      Resque.redis.set('worker:last_scaled', Time.now - 120)
      stub(TestJob).heroku_client { @fake_heroku_client }
    end

    it "should add the hook" do
      Resque::Plugin.failure_hooks(TestJob).should include(:on_failure_scale_workers)
    end

    it "should take whatever args Resque hands in" do
      Resque::Plugins::HerokuAutoscaler.class_eval("@@heroku_client = nil")
      stub(Heroku::Client).new { stub!.ps_scale }

      lambda { TestJob.on_failure_scale_workers("some", "random", "aguments", 42) }.should_not raise_error
    end
  end

  describe ".calculate_and_set_workers" do
    before do
      Resque.redis.set('worker:last_scaled', Time.now - 120)
      stub(TestJob).heroku_client { @fake_heroku_client }
    end

    context "when the queue is empty" do
      before do
        @now = Time.now
        Timecop.freeze(@now)
        stub(Resque).info { {:pending => 0} }
      end

      after { Timecop.return }

      it "should set workers to 0" do
        mock(TestJob).set_workers('worker', 0)
        TestJob.calculate_and_set_workers
      end

      it "sets last scaled time" do
        stub(TestJob).set_workers('worker', 0)

        TestJob.calculate_and_set_workers
        Resque.redis.get('worker:last_scaled').should == @now.to_s
      end
    end

    context "when the queue is not empty" do
      before do
        stub(Resque).info { {:pending => 1} }
      end

      it "should keep workers at 1" do
        dont_allow(TestJob).set_workers
        TestJob.calculate_and_set_workers
      end

      context "when scaling workers is disabled" do
        before do
          subject.config do |c|
            c.scaling_disabled = true
          end
        end

        it "should not use the heroku client" do
          dont_allow(TestJob).heroku_client
          TestJob.calculate_and_set_workers
        end
      end
    end

    context "when new_worker_count was changed" do
      before do
        @original_method = Resque::Plugins::HerokuAutoscaler::Config.instance_variable_get(:@new_worker_count)
        subject.config do |c|
          c.new_worker_count do
            2
          end
        end
      end

      after do
        Resque::Plugins::HerokuAutoscaler::Config.instance_variable_set(:@new_worker_count, @original_method)
      end

      it "should use the given block" do
        mock(TestJob).set_workers('worker', 2)
        TestJob.calculate_and_set_workers
      end
    end

    describe "when we changed the worker count in less than minimum wait time" do
      before do
        subject.config { |c| c.wait_time = 5}
        @last_set = Time.parse("00:00:00")
        Resque.redis.set('worker:last_scaled', @last_set)
      end

      after { Timecop.return }

      it "should not adjust the worker count" do
        Timecop.freeze(@last_set + 4)
        dont_allow(TestJob).set_workers
        TestJob.should_not be_time_to_scale
      end

      context "when there are no jobs left" do
        it "keeps checking for jobs and scales down if no job appeared" do
          Timecop.freeze(@last_set)
          mock(Resque).info.times(12) { {:pending => 0} }
          mock(Kernel).sleep(0.5).times(10) { Timecop.freeze(@last_set += 0.5) }
          mock(TestJob).set_workers('worker', 0)
          TestJob.calculate_and_set_workers
        end
      end
    end
  end

  describe ".set_workers" do
    it "should use the Heroku client to set the workers" do
      subject.config do |c|
        c.heroku_app = 'some_app_name'
      end

      stub(TestJob).current_workers { 0 }
      mock(TestJob).heroku_client { mock(@fake_heroku_client).ps_scale('some_app_name', { :type => 'worker', :qty => 10 }) }
      TestJob.set_workers('worker', 10)
    end
  end

  describe ".heroku_client" do
    before do
      subject.config do |c|
        c.heroku_user = 'john doe'
        c.heroku_pass = 'password'
      end
    end

    it "should return a heroku client" do
      Resque::Plugins::HerokuAutoscaler.class_eval("@@heroku_client = nil")
      TestJob.heroku_client.should be_a(Heroku::Client)
    end

    it "should use the right username and password" do
      Resque::Plugins::HerokuAutoscaler.class_eval("@@heroku_client = nil")
      mock(Heroku::Client).new('john doe', 'password')
      TestJob.heroku_client
    end

    it "should return the same client for multiple jobs" do
      a = 0
      stub(Heroku::Client).new { a += 1 }
      TestJob.heroku_client.should == TestJob.heroku_client
    end

    it "should share the same client across differnet job types" do
      a = 0
      stub(Heroku::Client).new { a += 1 }

      TestJob.heroku_client.should == AnotherJob.heroku_client
    end
  end

  describe ".config" do
    it "yields the configuration" do
      subject.config do |c|
        c.should == Resque::Plugins::HerokuAutoscaler::Config
      end
    end
  end

  describe ".current_workers" do
    it "should request the numbers of active workers from Heroku" do
      subject.config do |c|
        c.heroku_app = "my_app"
      end

      mock(TestJob).heroku_client { mock!.ps("my_app") { [{'process' => 'worker.1'},{'process' => 'worker.2'},{'process' => 'worker.3'},{'process' => 'worker.4'},{'process' => 'worker.5'},{'process' => 'worker.6'},{'process' => 'worker.7'},{'process' => 'worker.8'},{'process' => 'worker.9'},{'process' => 'worker.10'}] } }
      TestJob.current_workers('worker').should == 10
    end
  end
end
