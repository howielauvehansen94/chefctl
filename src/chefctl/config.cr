module Chefctl
  struct Config
    property server : String?
    property user : String?
    property key : String?
    property verify_ssl = true

    def initialize
      @server = ENV["CHEF_SERVER_URL"]?
      @user = ENV["CHEF_USER"]?
      @key = ENV["CHEF_KEY"]?
    end

    # `~` in the key path is expanded here because neither PowerShell nor
    # cmd expand it themselves, and environment variable values are never
    # expanded on any platform.
    def credentials : {String, String, String}?
      if (server = @server) && (user = @user) && (key = @key)
        {server, user, Path[key].expand(home: true).to_s}
      end
    end
  end
end
