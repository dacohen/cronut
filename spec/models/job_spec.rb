require 'spec_helper'

describe Job do
  after(:each) do
    Timecop.return
  end

  after(:all) do
    ActiveRecord::Base.connection.reset_pk_sequence!('jobs')
    ActiveRecord::Base.connection.reset_pk_sequence!('notifications')
  end

  it "cannot create object of Job without type" do
    expect {
      Job.create!({:name => "Test job"})
    }.to raise_error
  end

  describe "#last_successful_time_str" do
    it "returns the last scheduled time in the preferred time zone" do
      stub_const("TIME_ZONE", "America/Los_Angeles")

      job = IntervalJob.new
      job.last_successful_time = Time.utc(2014, 8, 7, 12)

      job.last_successful_time_str.should eq("August 7, 2014  5:00:00am PDT")
    end
  end

  describe "IntervalJobs" do
    describe "without buffer" do
      before(:each) do
        @start_time = Time.now
        @job = IntervalJob.create!({:name => "Test IntervalJob", :frequency => 600, :expected_run_time => 3600})
      end

      after(:each) do
        @job.destroy
      end

      it "initiates job's values" do
        @job.next_scheduled_time.to_i.should eq (@start_time + 600.seconds).to_i
        @job.last_successful_time.should be_nil
        @job.public_id.should_not be_nil
        @job.state.should eq :active
      end

      it "pinging does not update next scheduled time" do
        ping_time = Time.now
        @job.ping_start!
        @job.next_scheduled_time.to_i.should eq (ping_time + 600.seconds).to_i
        @job.last_successful_time.to_i.should eq ping_time.to_i
        @job.state.should eq :active

        @job.ping_end!
        @job.next_scheduled_time.to_i.should eq (ping_time + 600.seconds).to_i
        @job.last_successful_time.to_i.should eq ping_time.to_i
      end

      it "expiring postpones next scheduled time" do
        Timecop.travel(10.minutes)
        expire_time = Time.now
        @job.expire!
        @job.next_scheduled_time.to_i.should eq (expire_time + 600.seconds).to_i
        @job.last_successful_time.should be_nil
        @job.state.should eq :expired
      end

      it "expires" do
        @job.ping_start!
        Timecop.travel(11.minutes)
        expire_time = Time.now
        Job.check_expired_jobs
        @job.reload
        @job.next_scheduled_time.to_i.should >= (expire_time + 600.seconds).to_i
        @job.state.should eq :expired
      end

      it "expires and alerts notifications" do
        notification = PagerdutyNotification.create!({:name => "Test notification", :value => "dummy value"})
        notification.stub(:alert)
        notification.stub(:recover)
        @job.notifications << notification
        @job.save!

        notification.should_receive(:alert)
        notification.should_not_receive(:recover)
        @job.expire!
        @job.state.should eq :expired
      end

      it "expires and recovers" do
        notification = PagerdutyNotification.create!({:name => "Test notification", :value => "dummy value"})
        notification.stub(:alert)
        notification.stub(:recover)
        @job.notifications << notification
        @job.save!
        Timecop.travel(10.minutes)
        @job.expire!
        Timecop.travel(1.minutes)
        notification.should_not_receive(:alert)
        notification.should_receive(:recover)
        @job.ping_start!
      end

      it "change settings resets state and next scheduled time" do
        Timecop.travel(11.minutes)
        expire_time = Time.now
        @job.expire!
        @job.next_scheduled_time.to_i.should eq (expire_time + 600.seconds).to_i
        @job.last_successful_time.should be_nil
        @job.state.should eq :expired
        @job.frequency = 500
        change_time = Time.now
        @job.save!
        @job.reload
        @job.next_scheduled_time.to_i.should eq (change_time + 500.seconds).to_i
        @job.state.should eq :ready
      end
    end

    describe "with buffer" do
      before(:each) do
        @start_time = Time.now
        @job = IntervalJob.create!({:name => "Test IntervalJob", :frequency => 600, :buffer_time => 60, :expected_run_time => 3600, :state => :active})
      end

      after(:each) do
        @job.destroy
      end

      it "initiates job's values" do
        @job.next_scheduled_time.to_i.should eq (@start_time + 660.seconds).to_i
        @job.last_successful_time.should be_nil
        @job.public_id.should_not be_nil
        @job.state.should eq :active
      end

      it "pinging outside of buffer does not postpones next scheduled time" do
        Timecop.travel(1.minute)
        ping_time = Time.now
        @job.ping_start!
        @job.next_scheduled_time.to_i.should eq (@start_time + 660.seconds).to_i
        @job.last_successful_time.to_i.should eq ping_time.to_i
        @job.state.should eq :active
      end

      it "pinging within buffer postpones next scheduled time" do
        @job.ping_start!
        ping_time = Time.now
        Timecop.travel(9.minutes)
        @job.next_scheduled_time.to_i.should eq (ping_time + 660.seconds).to_i
        @job.last_successful_time.to_i.should eq ping_time.to_i
        @job.state.should eq :active
      end

      it "expiring postpones next scheduled time" do
        Timecop.travel(11.minutes)
        expire_time = Time.now
        @job.expire!
        @job.next_scheduled_time.to_i.should eq (expire_time + 660.seconds).to_i
        @job.last_successful_time.should be_nil
        @job.state.should eq :expired
      end

      it "expires" do
        @job.ping_start!
        expire_time = Time.now
        Timecop.travel(12.minutes)
        Job.check_expired_jobs
        @job.reload
        @job.next_scheduled_time.to_i.should >= (expire_time + 660.seconds).to_i
        @job.state.should eq :expired
      end

      it "expires and alerts notifications" do
        notification = PagerdutyNotification.create!({:name => "Test notification", :value => "dummy value"})
        notification.stub(:alert)
        notification.stub(:recover)
        @job.notifications << notification
        @job.save!
        Timecop.travel(11.minutes)
        notification.should_receive(:alert)
        notification.should_not_receive(:recover)
        @job.expire!
      end

      it "sends early alert if pinged too early" do
        notification = PagerdutyNotification.create!({:name => "Test notification", :value => "dummy value"})
        notification.stub(:alert)
        notification.stub(:early_alert)
        notification.stub(:recover)
        @job.notifications << notification
        @job.save!
        Timecop.travel(1.minute)
        notification.should_receive(:early_alert)
        notification.should_not_receive(:recover)
        @job.ping_start!
        @job.state.should eq :active
      end

      it "does not send early alert if job is already late" do
        notification = PagerdutyNotification.create!({:name => "Test notification", :value => "dummy value"})
        notification.stub(:alert)
        notification.stub(:early_alert)
        notification.stub(:recover)
        @job.notifications << notification
        @job.save!
        Timecop.travel(1.minute)
        @job.ping_start!
        Timecop.travel(10.minutes)
        notification.should_receive(:alert)
        @job.expire!
        Timecop.travel(2.minutes)
        # Job already expired, we shouldn't get another notification that this late ping is early
        notification.should_not_receive(:early_alert)
        notification.should_receive(:recover)
        @job.ping_end!
      end

      it "sends early alert if job is expired, late ping happened and the next ping was early" do
        notification = PagerdutyNotification.create!({:name => "Test notification", :value => "dummy value"})
        notification.stub(:alert)
        notification.stub(:early_alert)
        @job.notifications << notification
        @job.save!
        Timecop.travel(1.minute)
        @job.ping_start!
        Timecop.travel(10.minutes)
        @job.expire!
        Timecop.travel(2.minutes)
        @job.ping_end!
        Timecop.travel(1.minute)
        # We should get an early alert now, though
        notification.should_receive(:early_alert)
        @job.ping_start!
      end

      it "change settings resets status and next scheduled time" do
        Timecop.travel(11.minutes)
        expire_time = Time.now
        @job.expire!
        @job.next_scheduled_time.to_i.should eq (expire_time + 660.seconds).to_i
        @job.last_successful_time.should be_nil
        @job.state.should eq :expired
        @job.frequency = 500
        change_time = Time.now
        @job.save!
        @job.reload
        @job.next_scheduled_time.to_i.should eq (change_time + 560.seconds).to_i
        @job.state.should eq :ready
      end
    end
  end

  describe "CronJob" do
    describe "without buffer" do
      before(:each) do
        Timecop.travel(Time.at((Time.now.to_f / 600).floor * 600 + 1)) # round to nearest 10 mins
        @start_time = Time.now
        @next_time = Time.at((Time.now.to_f / 600).ceil * 600)
        @job = CronJob.create!({:name => "Test CronJob", :cron_expression => "*/10 * * * *", :expected_run_time => 60}) # every 10 mins , 1 minute run time
      end

      after(:each) do
        @job.destroy
      end

      it "initiates job's values" do
        @job.next_scheduled_time.to_i.should eq @next_time.to_i
        @job.last_successful_time.should be_nil
        @job.public_id.should_not be_nil
        @job.state.should eq :ready
      end

      it "ready ping_start on time" do
        @job.state.should eq :ready
        @job.ping_start!
        @job.state.should eq :running
      end

      it "ready ping_start early" do
        Timecop.travel(-5.minutes)
        @job.state.should eq :ready
        @job.ping_start!
        @job.state.should eq :ready
      end

      it "active ping_start early" do
        @job.force_active!
        Timecop.travel(-5.minutes)
        @job.state.should eq :active
        @job.ping_start!
        @job.state.should eq :active
      end

      it "active time_passed" do
        @job.force_active!
        @job.state.should eq :active
        Timecop.travel(10.seconds)
        Job.check_expired_jobs
        @job.reload
        @job.state.should eq :expired
      end

      it "running ping_end" do
        @job.force_run!
        @job.state.should eq :running
        @job.ping_end!
        @job.state.should eq :active
      end

      it "running runtime_exceeded" do
        @job.force_run!
        @job.state.should eq :running
        Timecop.travel(11.minutes)
        Job.check_expired_jobs
        @job.reload
        @job.state.should eq :hung
      end

      it "hung ping_end" do
        @job.hung!
        @job.state.should eq :hung
        @job.ping_end!
        @job.state.should eq :active
      end

      it "expired ping_start" do
        @job.expired!
        @job.state.should eq :expired
        @job.ping_start!
        @job.state.should eq :running
      end
    end

    describe "with buffer" do
      before(:each) do
        Timecop.travel(Time.at((Time.now.to_f / 600).floor * 600 + 1)) # round to nearest 10 mins
        @reference_time = Time.now - 1.seconds
        @start_time = Time.now
        @next_time = Time.at((Time.now.to_f / 600).ceil * 600)
        @job = CronJob.create!({:name => "Test CronJob", :cron_expression => "*/10 * * * *", :buffer_time => 60, :expected_run_time => 600}) # every 10 mins
      end

      after(:each) do
        @job.destroy
      end

      it "initiates job's values" do
        @job.next_scheduled_time.to_i.should eq @next_time.to_i
        @job.last_successful_time.should be_nil
        @job.public_id.should_not be_nil
        @job.state.should eq :ready
      end
      it "ready ping_start on time" do
        @job.state.should eq :ready
        @job.ping_start!
        @job.state.should eq :running
      end

      it "ready ping_start early" do
        Timecop.travel(-5.minutes)
        @job.state.should eq :ready
        @job.ping_start!
        @job.state.should eq :ready
      end

      it "active ping_start early" do
        @job.force_active!
        Timecop.travel(-5.minutes)
        @job.state.should eq :active
        @job.ping_start!
        @job.state.should eq :active
      end

      it "active time_passed" do
        @job.force_active!
        @job.state.should eq :active
        Timecop.travel(2.minutes)
        Job.check_expired_jobs
        @job.reload
        @job.state.should eq :expired
      end

      it "running ping_end" do
        @job.force_run!
        @job.state.should eq :running
        @job.ping_end!
        @job.state.should eq :active
      end

      it "running runtime_exceeded" do
        @job.force_run!
        @job.state.should eq :running
        Timecop.travel(11.minutes)
        Job.check_expired_jobs
        @job.reload
        @job.state.should eq :hung
      end

      it "hung ping_end" do
        @job.hung!
        @job.state.should eq :hung
        @job.ping_end!
        @job.state.should eq :active
      end

      it "expired ping_start" do
        @job.expired!
        @job.state.should eq :expired
        @job.ping_start!
        @job.state.should eq :running
      end

      it "change settings resets state and next scheduled time" do
        @job.state.should eq :ready
        @job.next_scheduled_time.to_i.should eq @next_time.to_i
        @job.last_successful_time.should be_nil
        @job.cron_expression = "*/5 * * * *"
        @job.save!
        @job.reload
        @job.next_scheduled_time.to_i.should eq (@reference_time + 300.seconds).to_i
        @job.state.should eq :ready
      end
    end
  end
end
