class ApplicationController < ActionController::Base
  protect_from_forgery

  DEFAULT_USERNAME = "admin"
  DEFAULT_PASSWORD = "password"

  before_filter :filter_for_ip_whitelist
  before_filter :basic_auth, :except => [:health]

  private

  def basic_auth
    authenticate_or_request_with_http_basic do |username, password|
      expected_username = ENV.fetch("CRONUT_USERNAME", DEFAULT_USERNAME)
      expected_password = ENV.fetch("CRONUT_PASSWORD", DEFAULT_PASSWORD)
      if username != expected_username
        puts "Failed username"
        return false
      end
      if expected_password == password
        @passed_auth=true
        return true
      end
      puts "ERROR: Failed basic auth"
      request_http_basic_authentication
      return false
    end
  end

  def ip_whitelist
    ENV["CRONUT_IP_WHITELIST"].to_s.split(",")
  end

  def filter_for_ip_whitelist
    ip = request.headers.fetch("X-Forwarded-For", request.ip)
    if ip_whitelist.any? && !ip_whitelist.include?(ip)
      puts "ERROR: Failed IP check for #{ip}"
      puts "You probably need to update the CRONUT_IP_WHITELIST env variable"
      return render json: "Unauthorized", status: 401
    end
  end
end
