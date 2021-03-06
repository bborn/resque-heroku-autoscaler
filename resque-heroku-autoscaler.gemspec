$LOAD_PATH.unshift 'lib'
require 'resque/plugins/heroku_autoscaler/version'

Gem::Specification.new do |s|
  s.name                     = "resque-heroku-autoscaler"
  s.date                     = Time.now.strftime('%Y-%m-%d')
  s.version                  = Resque::Plugins::HerokuAutoscaler::VERSION
  s.summary                  = "Resque plugin to autoscale your workers on Heroku"
  s.homepage                 = "https://github.com/ajmurmann/resque-heroku-autoscaler"
  s.authors                  = ["Alexander Murmann"]
  s.email                    = "ajmurmann@gmail.com"

  s.files                    = %w( README.md MIT.LICENSE Gemfile )
  s.files                    += Dir.glob("lib/**/*")
  s.files                    += Dir.glob("spec/**/*")

  s.add_dependency "resque", ">= 1.8"
  s.add_dependency "heroku"

  s.description       = <<desc
This gem scales your Heroku workers according to the number of pending Resque jobs. You can customize the scaling behavior of your workers, however you like.
desc
end