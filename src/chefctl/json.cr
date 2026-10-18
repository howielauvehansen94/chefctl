require "json"

module Chefctl
  module PrettyJSON
    def self.pretty(body : String) : String
      return "" if body.blank?

      String.build do |io|
        ::JSON.build(io, indent: "  ") { |b| ::JSON::PullParser.new(body).read_raw(b) }
      end
    end
  end
end
