class JobNotification < ActiveRecord::Base
  belongs_to :job
  belongs_to :notification


  def alert!
    begin
      self.last_event_key = notification.alert(job).incident_key
      save!
    rescue Exception => e
      puts "Exception on alert trigger for #{job.name} - #{notification.name}: #{e.inspect}"
    end
  end

  def early_alert
    begin
      self.last_event_key = notification.early_alert(job).incident_key
      self.save!
    rescue Exception => e
      puts "Exception on early alert trigger for #{job.name} - #{notification.name}: #{e.inspect}"
    end
  end

  def late_alert
    begin
      self.last_event_key = notification.late_alert(job).incident_key
      self.save!
    rescue Exception => e
      puts "Exception on late alert trigger for #{job.name} - #{notification.name}: #{e.inspect}"
    end
  end

  def recover!
    begin
      notification.recover(job, self.last_event_key)
    rescue Exception => e
      puts "Exception on recover alert trigger for #{job.name} - #{notification.name}: #{e.inspect}"
    end
    self.last_event_key = nil
    save!
  end
end
