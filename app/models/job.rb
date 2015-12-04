class Job < ActiveRecord::Base
  as_enum :state, %i{ready active running expired hung}

  has_many :job_notifications, :dependent => :destroy
  has_many :notifications, -> { uniq }, :through => :job_notifications

  before_create :create_public_id!, :if => ->{ self.public_id.blank?}

  default_scope ->{ order('state_cd DESC, name') }

  validates :name, :presence => true
  validates :expected_run_time, :presence => true

  def create_public_id!
    public_id = SecureRandom.hex(6).upcase
    collision = Job.find_by_public_id(public_id)

    while !collision.nil?
        public_id = SecureRandom.hex(6).upcase
        collision = Job.find_by_public_id(public_id)
    end

    self.public_id = public_id
    self.ready!
  end

  def ping_start!
    if self.ready? or self.active? then
      # If we just created the job, we might have just missed the previous scheduled time
      if between(Time.now(), self.next_scheduled_time).floor <= get_buffer_time or between(Time.now(), self.previous_scheduled_time).floor <= get_buffer_time then
        self.go_run!
      else
        job_notifications.each { |jn| jn.early_alert }
      end
    elsif self.expired? then
      self.go_run!
      job_notifications.each { |jn| jn.recover! }
    end
    self.save!
  end

  def ping_end!
    if self.running? then
      self.active!
    elsif self.hung? then
      self.active!
      job_notifications.each { |jn| jn.recover! }
    end
    self.save!
  end

  def runtime_exceeded!
    if self.running? then
      puts "#{self.name} expired"
      self.hung!
      job_notifications.each { |jn| jn.late_alert }
    end
    self.save!
  end

  def time_passed!
    if self.active? then
      puts "#{self.name} never ran"
      self.expired!
      job_notifications.each { |jn| jn.alert! }
    end
    self.save!
  end

  # Only for testing
  def force_run!
    self.go_run!
    self.save!
  end

  # Only for testing
  def force_active!
    self.active!
    # So next scheduled time is NOW, if possible
    self.last_successful_time = Time.now - 5.seconds
    self.save!
  end

  def go_run!
    self.running!
    self.last_successful_time = Time.now()
  end

  def buffer_time_str
    buffer_time ? Job.time_str(buffer_time) : "none"
  end

  def expected_run_time_str
    Job.time_str(expected_run_time)
  end

  def last_successful_time_str
    last_successful_time ? last_successful_time.in_time_zone(TIME_ZONE).strftime("%B %-d, %Y %l:%M:%S%P %Z") : "never"
  end

  def next_scheduled_time_str
    #now = self.last_successful_time ? self.last_successful_time : Time.now
    self.next_scheduled_time.in_time_zone(TIME_ZONE).strftime("%B %-d, %Y %l:%M:%S%P %Z")
  end

  def self.check_expired_jobs
    Job.all.each do |job|
      if job.last_successful_time and between(Time.now(), job.last_successful_time) >= job.expected_run_time + job.get_buffer_time then
        job.runtime_exceeded!
      end

      if (Time.now() > job.next_scheduled_time(job.last_successful_time)) and between(Time.now(), job.next_scheduled_time(job.last_successful_time)) >= job.get_buffer_time then
        job.time_passed!
      end
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

  def get_buffer_time
    (buffer_time ? buffer_time : 1).to_i
  end

  def between(start_time, end_time)
    TimeDifference.between(start_time, end_time).in_seconds
  end

  def self.between(start_time, end_time)
    TimeDifference.between(start_time, end_time).in_seconds
  end

end
