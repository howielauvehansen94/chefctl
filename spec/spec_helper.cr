require "spec"
require "../src/chefctl/cli"

def with_env(overrides : Hash(String, String | Nil), &)
  saved = overrides.keys.to_h { |key| {key, ENV[key]?} }
  overrides.each { |key, value| value ? (ENV[key] = value) : ENV.delete(key) }
  begin
    yield
  ensure
    saved.each { |key, value| value ? (ENV[key] = value) : ENV.delete(key) }
  end
end
