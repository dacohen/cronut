class StatusController < ApplicationController
  def health
    begin
      currentTime = ActiveRecord::Base.connection.select_value("SELECT CURRENT_TIME")
    rescue Exception => e
      render :text => "ERROR", :status => :service_unavailable, :layout => false
    end
    unless currentTime.nil? then
      render :text => "OK", :layout => false
    else
      render :text => "ERROR", :status => :service_unavailable, :layout => false
    end
  end
end
