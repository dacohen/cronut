class UpdateJobs < ActiveRecord::Migration
  def change
    remove_column :jobs, :next_scheduled_time
    add_column :jobs, :state_cd, :integer

    # Map old status to new states
    Job.all.each do |job|
      if job.status == "READY" then
        job.state_cd = 0
      elsif job.status == "ACTIVE" then
        job.state_cd = 1
      elsif job.status == "RUNNING" then
        job.state_cd = 2
      elsif job.status == "EXPIRED" then
        job.state_cd = 3
      elsif job.status == "HUNG" then
        job.state_cd = 4
      end
      job.save!
    end

    remove_column :jobs, :status
  end
end
