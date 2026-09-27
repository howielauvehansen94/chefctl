# --- Example ---
# chef = Chef::Client.new("https://chef.example.com/organizations/myorg",
#                         "myuser", "#{ENV["HOME"]}/.chef/myuser.pem")
#
# chef.get("nodes").as_h.each_key { |name| puts name }
# node = chef.get("nodes/web01")
# puts node["automatic"]["platform"]
#
# # Search
# results = chef.get("search/node?q=platform:ubuntu&rows=100")
#
# # Update an attribute (read-modify-write the whole node object)
# n = chef.get("nodes/web01").as_h
# normal = n["normal"].as_h
# normal["foo"] = JSON::Any.new("bar")
# chef.put("nodes/web01", n)

require "http/client"
require "json"
require "uri"
require "base64"
require "openssl"
require "openssl_ext"

module Chef
  class Error < Exception
    getter status : Int32
    def initialize(@status, body : String)
      super("Chef API #{@status}: #{body}")
    end
  end

  class Client
    API_VERSION = "1"

    def initialize(@server_url : String, @client_name : String, key_path : String,
                   @verify_ssl : Bool = true)
      @uri = URI.parse(@server_url) # e.g. https://chef.example.com/organizations/myorg
      @key = OpenSSL::PKey::RSA.new(File.read(key_path))
    end

    def get(path : String)
      request("GET", path)
    end

    def delete(path : String)
      request("DELETE", path)
    end

    def post(path : String, body : JSON::Any | Hash | NamedTuple)
      request("POST", path, body.to_json)
    end

    def put(path : String, body : JSON::Any | Hash | NamedTuple)
      request("PUT", path, body.to_json)
    end

    def request(method : String, path : String, body : String = "") : JSON::Any
      full_path = canonical_path("#{@uri.path}/#{path}")
      query = nil
      if idx = path.index('?')
        full_path = canonical_path("#{@uri.path}/#{path[0...idx]}")
        query = path[(idx + 1)..]
      end

      headers = HTTP::Headers{
        "Accept"       => "application/json",
        "Content-Type" => "application/json",
        "X-Chef-Version" => "18.0.0",
      }
      sign!(headers, method, full_path, body)

      tls = nil
      if @uri.scheme == "https"
        tls = OpenSSL::SSL::Context::Client.new
        tls.verify_mode = OpenSSL::SSL::VerifyMode::NONE unless @verify_ssl
      end

      client = HTTP::Client.new(@uri.host.not_nil!, @uri.port, tls: tls)
      target = query ? "#{full_path}?#{query}" : full_path
      resp = client.exec(method, target, headers: headers, body: body.empty? ? nil : body)
      raise Error.new(resp.status_code, resp.body) unless resp.success?
      resp.body.empty? ? JSON::Any.new(nil) : JSON.parse(resp.body)
    ensure
      client.try &.close
    end

    private def sign!(headers : HTTP::Headers, method : String, path : String, body : String)
      timestamp    = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
      content_hash = Base64.strict_encode(OpenSSL::Digest.new("SHA256").update(body).final)

      canonical = [
        "Method:#{method.upcase}",
        "Path:#{path}",
        "X-Ops-Content-Hash:#{content_hash}",
        "X-Ops-Sign:version=1.3",
        "X-Ops-Timestamp:#{timestamp}",
        "X-Ops-UserId:#{@client_name}",
        "X-Ops-Server-API-Version:#{API_VERSION}",
      ].join("\n")

      signature = Base64.strict_encode(@key.sign(OpenSSL::Digest.new("SHA256"), canonical))

      headers["X-Ops-Sign"] = "algorithm=sha256;version=1.3"
      headers["X-Ops-Userid"] = @client_name
      headers["X-Ops-Timestamp"] = timestamp
      headers["X-Ops-Content-Hash"] = content_hash
      headers["X-Ops-Server-API-Version"] = API_VERSION

      signature.scan(/.{1,60}/).each_with_index do |m, i|
        headers["X-Ops-Authorization-#{i + 1}"] = m[0]
      end
    end

    private def canonical_path(p : String) : String
      p = p.gsub(/\/+/, "/")
      p.size > 1 ? p.chomp("/") : p
    end
  end
end
