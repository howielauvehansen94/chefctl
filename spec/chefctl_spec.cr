require "./spec_helper"

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
    cli.@config.verify_ssl.should be_false
    cli.parser.parse(["--verify-ssl"])
    cli.@config.verify_ssl.should be_true
  end

  it "requires server config before contacting the API" do
    with_env({"CHEF_SERVER_URL" => nil, "CHEF_USER" => nil, "CHEF_KEY" => nil}) do
      Chefctl::CLI.run(["nodes"]).should eq(1)
    end
  end
end
