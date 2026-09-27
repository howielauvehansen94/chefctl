require "option_parser"
require "../utils/chef_api"

module Chefctl
  VERSION = "0.1.0"

  class CLI
    def self.run(argv)
      server = ENV["CHEF_SERVER_URL"]?
      user = ENV["CHEF_USER"]?
      key = ENV["CHEF_KEY"]?
      verify_ssl = true
      # OptionParser captures handler blocks, so they can't return from run;
      # they set exit_early and run returns it after parsing.
      exit_early : Int32? = nil

      parser = OptionParser.new do |p|
        p.banner = <<-USAGE
          Usage: chefctl [flags] <command> [args]

          Commands:
            nodes          list node names
            node NAME      show a node (pretty JSON)
            clients        list client names
            client NAME    show a client (pretty JSON)
            roles          list role names
            environments   list environment names
            cookbooks      list cookbook names
            get PATH       raw GET, org-relative, e.g. "search/node?q=platform:ubuntu"
            version        print version
            help           show this help

          Flags:
          USAGE

        p.on("--server URL", "Chef server org URL (default: $CHEF_SERVER_URL)") { |v| server = v }
        p.on("--user NAME", "API user/client name (default: $CHEF_USER)") { |v| user = v }
        p.on("--key PATH", "client private key path (default: $CHEF_KEY)") { |v| key = v }
        p.on("--no-verify-ssl", "skip TLS certificate verification") { verify_ssl = false }
        p.on("-h", "--help", "show help") { puts p; exit_early = 0 }
        p.on("-v", "--version", "print version") { puts VERSION; exit_early = 0 }
      end

      args = argv.dup
      parser.parse(args)
      if exit_code = exit_early
        return exit_code
      end

      command = args.shift?
      unless command
        puts parser
        return 1
      end

      case command
      when "help"
        puts parser
        0
      when "version"
        puts VERSION
        0
        # The command name is the endpoint, and each GET returns a name => url hash.
      when "nodes", "clients", "roles", "environments", "cookbooks"
        with_client(server, user, key, verify_ssl) do |chef|
          chef.get(command).as_h.each_key { |name| puts name }
          0
        end
      when "node", "client"
        name = args.shift?
        unless name
          STDERR.puts "usage: chefctl #{command} NAME"
          return 1
        end
        with_client(server, user, key, verify_ssl) do |chef|
          puts chef.get("#{command}s/#{name}").to_pretty_json
          0
        end
      when "get"
        path = args.shift?
        unless path
          STDERR.puts %(usage: chefctl get PATH  # org-relative, e.g. search/node?q=platform:ubuntu)
          return 1
        end
        with_client(server, user, key, verify_ssl) do |chef|
          puts chef.get(path).to_pretty_json
          0
        end
      else
        STDERR.puts "unknown command: #{command}"
        STDERR.puts parser
        1
      end
    rescue ex : Chef::Error
      STDERR.puts ex.message
      1
    rescue ex : OptionParser::Exception
      STDERR.puts ex.message.not_nil!
      STDERR.puts parser
      1
    rescue ex
      STDERR.puts "error: #{ex.message}"
      1
    end

    private def self.with_client(server, user, key, verify_ssl, &)
      unless server && user && key
        STDERR.puts "missing config: set --server/--user/--key or $CHEF_SERVER_URL/$CHEF_USER/$CHEF_KEY"
        return 1
      end
      yield Chef::Client.new(server.not_nil!, user.not_nil!, key.not_nil!, verify_ssl)
    end
  end
end
