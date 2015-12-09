class IntervalJob < Job
  validates :frequency, :presence => true

  def self.model_name
    superclass.model_name
  end

  def frequency_str
    return Job.time_str(frequency)
  end

  def next_scheduled_time(now = Time.now)
    now + frequency.seconds
  end

  def previous_scheduled_time(now = Time.now)
    now - frequency.seconds
  end

end
