class CronJob < Job
  validates :cron_expression, :presence => true
  validate :validate_cron_expression

  def self.model_name
    superclass.model_name
  end


  def next_scheduled_time(now = Time.now)
    validate_cron_expression
    Rufus::Scheduler.parse(cron_expression).next_time(now)
  end

  def previous_scheduled_time(now = Time.now)
    validate_cron_expression
    Rufus::Scheduler.parse(cron_expression).previous_time(now)
  end

  private
  def validate_cron_expression
    values = cron_expression.split

    if values.length < 5 || values.length > 6
      self.errors.add(:cron_expression, "invalid value")
    else
      begin
        attempt_to_parse = Rufus::Scheduler.parse(cron_expression)
      rescue Exception => e
        self.errors.add(:cron_expression, "not a valid cronline")
      end
    end
  end
end
