require "./spec_helper"
require "../src/chefctl/config"

describe Chefctl::Config do
  server = "https://chef.example.com/organizations/myorg"

  it "reads credentials from the environment" do
    with_env({"CHEF_SERVER_URL" => server, "CHEF_USER" => "admin", "CHEF_KEY" => "~"}) do
      Chefctl::Config.new.credentials.should eq({server, "admin", Path.home.to_s})
    end
  end

  it "expands ~ in the key path against the user's home directory" do
    with_env({"CHEF_SERVER_URL" => server, "CHEF_USER" => "admin", "CHEF_KEY" => "~/.chef/admin.pem"}) do
      key = (Path.home / ".chef" / "admin.pem").to_s
      Chefctl::Config.new.credentials.should eq({server, "admin", key})
    end
  end

  it "prefers values assigned after construction" do
    with_env({"CHEF_SERVER_URL" => server, "CHEF_USER" => "admin", "CHEF_KEY" => "~/.chef/ignored.pem"}) do
      config = Chefctl::Config.new
      config.user = "client"
      config.key = "client.pem"
      key = Path["client.pem"].expand.to_s
      config.credentials.should eq({server, "client", key})
    end
  end

  it "returns nil unless server, user, and key are all set" do
    with_env({"CHEF_USER" => "admin"}) do
      Chefctl::Config.new.credentials.should be_nil
    end
  end
end
