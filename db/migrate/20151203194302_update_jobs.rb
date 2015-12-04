class UpdateJobs < ActiveRecord::Migration
  def change
    remove_column :jobs, :next_scheduled_time
    remove_column :jobs, :status
    add_column :jobs, :state_cd, :integer
  end
end
