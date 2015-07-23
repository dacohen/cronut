class AddExpectedRunTime < ActiveRecord::Migration
  def up
    add_column :jobs, :expected_run_time, :integer
    add_column :jobs, :next_end_time, :datetime
  end

  def down
    remove_column :jobs, :expected_run_time
    remove_column :jobs, :next_end_time
  end
end
