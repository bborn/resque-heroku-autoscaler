module Resque::Plugins::HerokuAutoscaler
  class RailsAutoscaler < Rails::Railtie
    initializer 'heroku.autoscaler.configure_api_key' do
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
  end
end
