module Resque::Plugins::HerokuAutoscaler
  class RailsAutoscaler < Rails::Railtie    
    initializer 'heroku.autoscaler.configure_api_key' do
      require 'heroku'
      require 'resque/plugins/resque_heroku_autoscaler'
      
      Resque::Plugins::HerokuAutoscaler.config do |c|
        c.heroku_user         = ''
        begin
          c.heroku_pass       = ENV['HEROKU_API_KEY'].to_s.split('@').last
          c.heroku_app        = ENV['HEROKU_API_KEY'].to_s.split('@').first
          c.scaling_disabled  = false
        rescue
          c.scaling_disabled  = true
          raise "[ERROR] Please set HEROKU_API_KEY ('app-name@api-key') to enable worker auto-scaling"
        end
      end
    end
    
    initializer 'heroku.autoscaler.configure_worker_count' do
      Resque::Plugins::HerokuAutoscaler.config do |c|
        c.new_worker_count do |pending|
          if pending.zero?
            0
          elsif pending < 3
            1
          elsif pending > 50
            50
          else
            (pending/2).ceil.to_i
          end
        end
      end
    end
    
    initializer 'heroku.autoscaler.make_cacheable' do
      require 'resque/plugins/heroku_autoscaler/cacheable'
      # Now we'll only change the Heroku worker scale every 60 seconds or so, 
      # saves a lot of problems when you're running thousands of jobs at a time
      Resque::Plugins::HerokuAutoscaler.cachify!
    end
  end
end
