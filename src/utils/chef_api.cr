require "http/client"
require "json"
require "uri"
require "base64"
require "openssl"
require "openssl_ext"

module Chef
  class Error < Exception
    getter status

    def initialize(@status : Int32, body)
      super("Chef API #{@status}: #{body}")
    end
  end

  class Client
    API_VERSION = "1"

    def initialize(@server_url : String, @client_name : String, key_path, @verify_ssl : Bool = true)
      @uri = URI.parse(@server_url)
      @key = OpenSSL::PKey::RSA.new(File.read(key_path))
    end

    def get(path)
      request("GET", path)
    end

    def delete(path)
      request("DELETE", path)
    end

    def post(path, body : JSON::Any | Hash | NamedTuple)
      request("POST", path, body.to_json)
    end

    def put(path, body : JSON::Any | Hash | NamedTuple)
      request("PUT", path, body.to_json)
    end

    # Raw GET body, for payloads JSON.parse cannot represent (u64 attributes
    # like automatic/sysconf/ULONG_MAX exceed Int64).
    def get_raw(path)
      perform("GET", path, "")
    end

    def request(method, path, body = "")
      raw = perform(method, path, body)
      raw.empty? ? JSON::Any.new(nil) : JSON.parse(raw)
    end

    private def perform(method, path, body)
      full_path = canonical_path("#{@uri.path}/#{path}")
      query = nil
      # The signature covers the path only; the query string rides along in the request URL.
      if idx = path.index('?')
        full_path = canonical_path("#{@uri.path}/#{path[0...idx]}")
        query = path[(idx + 1)..]
      end

      headers = HTTP::Headers{
        "Accept"         => "application/json",
        "Content-Type"   => "application/json",
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
      resp.body
    ensure
      client.try &.close
    end

    private def sign!(headers, method, path, body)
      timestamp = Time.utc.to_s("%Y-%m-%dT%H:%M:%SZ")
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

      # The protocol carries the signature split across 60-char X-Ops-Authorization-N headers.
      signature.scan(/.{1,60}/).each_with_index do |m, i|
        headers["X-Ops-Authorization-#{i + 1}"] = m[0]
      end
    end

    private def canonical_path(p)
      p = p.gsub(/\/+/, "/")
      p.size > 1 ? p.chomp("/") : p
    end
  end
end
