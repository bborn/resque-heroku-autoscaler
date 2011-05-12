module Resque::Plugins::HerokuAutoscaler
  def self.cachify!
    alias_method_chain :set_workers, :cache
    alias_method_chain :current_workers, :cache
  end
  
  def set_workers_with_cache number_of_workers
    Rails.cache.fetch('heroku.worker.refresh', :expires_in => 10.seconds) do
      Rails.cache.write('heroku.worker.count', set_workers_without_cache(number_of_workers), :expires_in => 1.minute)
    end
  end

  def current_workers_with_cache
    Rails.cache.fetch('heroku.worker.count', :expires_in => 1.minute) do
      current_workers_without_cache.tap do |count|
        Rails.cache.delete 'heroku.worker.refresh' if count.zero?
      end
    end
  end
end
