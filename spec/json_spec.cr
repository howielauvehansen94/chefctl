require "./spec_helper"

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
