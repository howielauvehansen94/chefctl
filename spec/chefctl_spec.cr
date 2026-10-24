require "spec"
require "../src/chefctl"

def with_env(overrides : Hash(String, String?), &)
  saved = overrides.keys.to_h { |key| {key, ENV[key]?} }
  overrides.each { |key, value| value ? (ENV[key] = value) : ENV.delete(key) }
  begin
    yield
  ensure
    saved.each { |key, value| value ? (ENV[key] = value) : ENV.delete(key) }
  end
end

describe Chefctl::PrettyJSON do
  it "pretty-prints JSON with values beyond Int64 (sysconf ULONG_MAX)" do
    json = %({"automatic": {"sysconf": {"ULONG_MAX": 18446744073709551615}}})
    Chefctl::PrettyJSON.pretty(json).should contain(%("ULONG_MAX": 18446744073709551615))
  end

  it "returns an empty string for an empty or whitespace-only body" do
    Chefctl::PrettyJSON.pretty("").should eq("")
    Chefctl::PrettyJSON.pretty("   \n").should eq("")
  end
end

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

describe Chefctl::CLI do
  it "runs version without touching the network" do
    Chefctl::CLI.run(["version"]).should eq(0)
  end

  it "rejects unknown commands" do
    Chefctl::CLI.run(["frobnicate"]).should eq(1)
  end

  it "shows help for the --help flag" do
    Chefctl::CLI.run(["--help"]).should eq(0)
  end

  it "prints usage when node is called without a name" do
    Chefctl::CLI.run(["node"]).should eq(1)
  end

  it "prints usage when get is called without a path" do
    Chefctl::CLI.run(["get"]).should eq(1)
  end

  it "reports unknown flags" do
    Chefctl::CLI.run(["--frobnicate"]).should eq(1)
  end

  it "lets the last TLS flag win" do
    cli = Chefctl::CLI.new
    cli.parser.parse(["--no-verify-ssl"])
    cli.@config.verify_ssl?.should be_false
    cli.parser.parse(["--verify-ssl"])
    cli.@config.verify_ssl?.should be_true
  end

  it "requires server config before contacting the API" do
    with_env({"CHEF_SERVER_URL" => nil, "CHEF_USER" => nil, "CHEF_KEY" => nil}) do
      Chefctl::CLI.run(["nodes"]).should eq(1)
    end
  end
end
