require 'rails_helper'

RSpec.describe StatusController, type: :controller do

  it "should return OK" do
    get :health
    response.body.should eq "OK"
    response.status.should eq 200
  end

end
