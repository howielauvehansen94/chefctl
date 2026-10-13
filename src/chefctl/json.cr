module Chefctl
  module JSON
    def self.pretty(body : String) : String
      String.build do |io|
        ::JSON.build(io, indent: "  ") { |b| ::JSON::PullParser.new(body).read_raw(b) }
      end
    end
  end
end
