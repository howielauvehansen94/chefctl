require "./spec_helper"

describe Chefctl::JSON do
  it "pretty-prints JSON with values beyond Int64 (sysconf ULONG_MAX)" do
    json = %({"automatic": {"sysconf": {"ULONG_MAX": 18446744073709551615}}})
    Chefctl::JSON.pretty(json).should contain(%("ULONG_MAX": 18446744073709551615))
  end
end
