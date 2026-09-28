require "./spec_helper"

describe Chefctl::CLI do
  it "runs version without touching the network" do
    Chefctl::CLI.run(["version"]).should eq(0)
  end

  it "rejects unknown commands" do
    Chefctl::CLI.run(["frobnicate"]).should eq(1)
  end

  it "pretty-prints node JSON with values beyond Int64 (sysconf ULONG_MAX)" do
    json = %({"automatic": {"sysconf": {"ULONG_MAX": 18446744073709551615}}})
    Chefctl::CLI.pretty_json(json).should contain(%("ULONG_MAX": 18446744073709551615))
  end

  it "requires server config before contacting the API" do
    keys = {"CHEF_SERVER_URL", "CHEF_USER", "CHEF_KEY"}
    saved = keys.to_h { |k| {k, ENV[k]?} }
    keys.each { |k| ENV.delete(k) }
    begin
      Chefctl::CLI.run(["nodes"]).should eq(1)
    ensure
      saved.each { |k, v| v ? (ENV[k] = v) : ENV.delete(k) }
    end
  end
end
