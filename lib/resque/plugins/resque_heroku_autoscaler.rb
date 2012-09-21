require 'resque/plugins/heroku_autoscaler/config'
require 'heroku'

module Resque
  module Plugins
    module HerokuAutoscaler
      @@heroku_client = nil

      def after_enqueue_scale_workers_up(*args)
        calculate_and_set_workers
      end

      def after_perform_scale_workers(*args)
        calculate_and_set_workers
      end

      def on_failure_scale_workers(*args)
        calculate_and_set_workers
      end

      def set_workers(process, number_of_workers)
        if number_of_workers != current_workers(process)
          heroku_client.ps_scale(Resque::Plugins::HerokuAutoscaler::Config.heroku_app,
                                :type => process, :qty => number_of_workers)
        end
      end

      def current_workers(process)
        heroku_client.ps(Resque::Plugins::HerokuAutoscaler::Config.heroku_app).count { |p| p["process"].match(process) != nil }
      end

      def heroku_client
        @@heroku_client || @@heroku_client = Heroku::Client.new(Resque::Plugins::HerokuAutoscaler::Config.heroku_user,
                                                                Resque::Plugins::HerokuAutoscaler::Config.heroku_pass)
      end

      def self.config
        yield Resque::Plugins::HerokuAutoscaler::Config
      end

      def calculate_and_set_workers
        unless Resque::Plugins::HerokuAutoscaler::Config.scaling_disabled?
          wait_for_task_or_scale
          if time_to_scale?
            scale
          end
        end
      end

      private

      def scale
        Resque::Plugins::HerokuAutoscaler::Config.process_list.each do |process|
          begin
            current_count = current_workers(process)
            new_count = Resque::Plugins::HerokuAutoscaler::Config.new_worker_count(Resque.info[:pending], process, current_count)
            set_workers(process, new_count) if new_count != current_count
            Resque.redis.set("#{process}:last_scaled", Time.now)
          rescue RestClient::Exception => client_error
            log client_error
          end
        end
      end

      def wait_for_task_or_scale
        until Resque.info[:pending] > 0 || time_to_scale?
          Kernel.sleep(0.5)
        end
      end

      def time_to_scale?
        Resque::Plugins::HerokuAutoscaler::Config.process_list.count { |process| time_to_scale_process?(process) } > 0
      end

      def time_to_scale_process?(process)
        return true if !Resque.redis.get("#{process}:last_scaled")        
        (Time.now - Time.parse(Resque.redis.get("#{process}:last_scaled"))) >= Resque::Plugins::HerokuAutoscaler::Config.wait_time
      end

      def log(message)
        if defined?(Rails)
          Rails.logger.info(message)
        else
          puts message
        end
      end
    end
  end
end