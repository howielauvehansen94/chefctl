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

    def get_raw(path)
      perform("GET", path, "")
    end

    def request(method, path, body = "")
      raw = perform(method, path, body)
      raw.empty? ? JSON::Any.new(nil) : JSON.parse(raw)
    end

    private def perform(method, path, body)
      # Query string is excluded from the signed path but sent on the request.
      full_path = canonical_path("#{@uri.path}/#{path}")
      query = nil
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

      # Chef API v1.3 signed-header authentication: the canonical string is
      # RSA-signed and the result split across numbered headers.
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

      # Chef limits individual header line length, so the signature is split
      # into 60-char chunks across numbered X-Ops-Authorization-N headers.
      signature.scan(/.{1,60}/).each_with_index do |m, i|
        headers["X-Ops-Authorization-#{i + 1}"] = m[0]
      end
    end

    # The server normalizes the path before verifying the signature, so the
    # signed path must match (collapse repeated slashes, strip trailing slash).
    private def canonical_path(p)
      p = p.gsub(/\/+/, "/")
      p.size > 1 ? p.chomp("/") : p
    end
  end
end
