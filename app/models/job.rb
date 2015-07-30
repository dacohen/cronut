class Job < ActiveRecord::Base
  has_many :job_notifications, :dependent => :destroy
  has_many :notifications, -> { uniq }, :through => :job_notifications

  before_create :create_public_id!, :if => ->{ self.public_id.blank?}
  before_create :initial_scheduled_time!, :if => ->{ self.next_scheduled_time.blank? }
  before_create :reset_status!
  before_save :reset_status!, :set_next_scheduled_time!, :if => :timing_changed

  default_scope ->{ order('next_scheduled_time, name') }

  validates :name, :presence => true
  validates :expected_run_time, :presence => true
  validates_inclusion_of :status, :in => ["READY", "ACTIVE", "EXPIRED", "HUNG", "RUNNING"]

  def create_public_id!
    public_id = SecureRandom.hex(6).upcase
    collision = Job.find_by_public_id(public_id)

    while !collision.nil?
        public_id = SecureRandom.hex(6).upcase
        collision = Job.find_by_public_id(public_id)
    end

    self.public_id = public_id
  end

  def ping_start!
    self.last_successful_time = Time.now
    set_current_end_time
    check_if_ping_is_too_early
    check_if_job_recovered
    puts "Pinging job #{self.name}"
    self.status = "RUNNING"
    self.save!
  end

  def ping_end!
    next_scheduled_time!
    set_next_end_time
    check_if_job_recovered
    puts "Stopping job #{self.name}"
    self.status = "ACTIVE"
    self.save!
  end

  def expire!
    if self.status == "ACTIVE" then
      self.status = "EXPIRED"
        job_notifications.each { |jn|
          jn.alert!
        }
      set_next_scheduled_time!
      self.save!
    end
  end

  def hung!
    if self.status == "RUNNING" then
      self.status = "HUNG"
      job_notifications.each do |jn|
        jn.late_alert
      end

      set_next_end_time
      self.save!

    end
  end

  def extra_time
    return (buffer_time ? buffer_time : 0).seconds
  end

  def buffer_time_str
    return buffer_time ? Job.time_str(buffer_time) : "none"
  end

  def last_successful_time_str
    return last_successful_time ? last_successful_time.in_time_zone(TIME_ZONE).strftime("%B %-d, %Y %l:%M:%S%P %Z") : "never"
  end

  def next_scheduled_time_str
    return next_scheduled_time.in_time_zone(TIME_ZONE).strftime("%B %-d, %Y %l:%M:%S%P %Z")
  end

  def self.check_expired_jobs
    expired_jobs = Job.where("next_scheduled_time < ?", Time.now)
    puts "#{expired_jobs.length} jobs expired"

    expired_jobs.each { |job|
      puts "Job: #{job.name} expired"
      job.expire!
    }

    hung_jobs = Job.where("next_end_time < ?", Time.now)
    puts "#{hung_jobs.length} jobs hung"

    hung_jobs.each do |job|
      puts "Job: #{job.name} hung"
      job.hung!
    end
  end

  def self.time_str(seconds)
    if seconds % 2629740 == 0
      num = seconds / 2629740
      unit = "month"
    elsif seconds % 604800 == 0
      num = seconds / 604800
      unit = "week"
    elsif seconds % 86400 == 0
      num = seconds / 604800
      unit = "day"
    elsif seconds % 3600 == 0
      num = seconds / 3600
      unit = "hour"
    elsif seconds % 60 == 0
      num = seconds / 60
      unit = "minute"
    else
      num = seconds
      unit = "second"
    end

    return "#{num} #{unit.pluralize(num)}"
  end

  private
  def check_if_ping_is_too_early
    # If the job had already expired, we don't want the subsequent ping to be considered "early"
    if buffer_time && self.status != "EXPIRED"
      if last_successful_time < next_scheduled_time - (buffer_time * 2).seconds
        job_notifications.each { |jn|
          jn.early_alert
        }
      end
    end
  end

  def check_if_job_recovered
    if self.status == "EXPIRED" or self.status == "HUNG" then
      job_notifications.each { |jn|
        jn.recover!
      }
    end
  end

  def calculate_next_scheduled_time(now = Time.now)
    raise "ERROR: calculate_next_scheduled_time must be defined"
  end

  def set_next_scheduled_time!
    self.next_scheduled_time = calculate_next_scheduled_time
  end

  def set_next_end_time
    self.next_end_time = self.next_scheduled_time + self.expected_run_time.seconds
  end

  def set_current_end_time
    self.next_end_time = self.last_successful_time + self.expected_run_time.seconds
  end

  def reset_status!
    self.status = "READY" if !self.status_changed? && !self.last_successful_time_changed?
  end

  def initial_scheduled_time!
    self.next_scheduled_time = calculate_next_scheduled_time
  end

  def timing_changed
    self.frequency_changed? or self.cron_expression_changed? or self.expected_run_time_changed?
  end

end
