module Chefctl
  # Renders Chef server JSON for humans.
  #
  # JSON.parse only holds Int64 and raises on u64 values Ohai reports
  # (e.g. automatic/sysconf/ULONG_MAX), so display JSON is streamed raw
  # through a pull parser instead of round-tripped through JSON::Any.
  module JSON
    def self.pretty(body : String) : String
      String.build do |io|
        ::JSON.build(io, indent: "  ") { |b| ::JSON::PullParser.new(body).read_raw(b) }
      end
    end
  end
end
