require "option_parser"
require "chef-auth"

module Chefctl
  VERSION = "0.1.0" # x-release-please-version

  class CLI
    SUCCESS = 0
    FAILURE = 1

    # Connection settings, gathered from environment variables and overridden
    # by command-line flags.
    private struct Config
      property server : String?
      property user : String?
      property key : String?
      property verify_ssl = true

      def initialize
        @server = ENV["CHEF_SERVER_URL"]?
        @user = ENV["CHEF_USER"]?
        @key = ENV["CHEF_KEY"]?
      end

      # The three values Chef::Client needs, or nil if any is missing.
      def credentials : {String, String, String}?
        if (server = @server) && (user = @user) && (key = @key)
          {server, user, key}
        end
      end
    end

    getter parser : OptionParser

    @config = Config.new

    # OptionParser handler blocks cannot return from run, so the --help and
    # --version handlers record the exit code here and run returns it after
    # parsing finishes.
    @exit_code : Int32? = nil

    def initialize
      @parser = build_parser
    end

    def self.run(argv) : Int32
      cli = new
      cli.run(argv)
    rescue ex : Chef::Error
      STDERR.puts ex.message
      FAILURE
    rescue ex : OptionParser::Exception
      STDERR.puts ex.message || "invalid option"
      STDERR.puts new.parser
      FAILURE
    rescue ex
      STDERR.puts "error: #{ex.message}"
      FAILURE
    end

    # JSON.parse only holds Int64 and raises on u64 values Ohai reports
    # (e.g. automatic/sysconf/ULONG_MAX), so display JSON is streamed raw
    # through a pull parser instead of round-tripped through JSON::Any.
    def self.pretty_json(body : String) : String
      String.build do |io|
        JSON.build(io, indent: "  ") { |b| JSON::PullParser.new(body).read_raw(b) }
      end
    end

    # Parses flags, then hands the remaining arguments to the matching command.
    def run(argv : Array(String)) : Int32
      args = argv.dup
      parser.parse(args)
      if exit_code = @exit_code
        return exit_code
      end

      command = args.shift?
      unless command
        puts parser
        return FAILURE
      end

      dispatch(command, args)
    end

    private def dispatch(command : String, args : Array(String)) : Int32
      case command
      when "help"
        puts parser
        SUCCESS
      when "version"
        puts VERSION
        SUCCESS
      when "nodes", "clients", "roles", "environments", "cookbooks"
        with_client { |chef| list_names(chef, command) }
      when "node", "client"
        name = args.shift?
        return usage_error("usage: chefctl #{command} NAME") unless name
        with_client { |chef| show_raw(chef, "#{command}s/#{name}") }
      when "get"
        path = args.shift?
        return usage_error(%(usage: chefctl get PATH  # org-relative, e.g. search/node?q=platform:ubuntu)) unless path
        with_client { |chef| show_raw(chef, path) }
      else
        STDERR.puts "unknown command: #{command}"
        STDERR.puts parser
        FAILURE
      end
    end

    # The command name is the endpoint, and each listing endpoint returns a
    # name => URL hash whose keys are the resource names.
    private def list_names(chef : Chef::Client, endpoint : String) : Int32
      chef.get(endpoint).as_h.each_key { |name| puts name }
      SUCCESS
    end

    private def show_raw(chef : Chef::Client, path : String) : Int32
      puts CLI.pretty_json(chef.get_raw(path))
      SUCCESS
    end

    private def with_client(&)
      credentials = @config.credentials
      unless credentials
        STDERR.puts "missing config: set --server/--user/--key or $CHEF_SERVER_URL/$CHEF_USER/$CHEF_KEY"
        return FAILURE
      end
      server, user, key = credentials
      yield Chef::Client.new(server, user, key, @config.verify_ssl)
    end

    private def usage_error(message : String) : Int32
      STDERR.puts message
      FAILURE
    end

    private def build_parser : OptionParser
      OptionParser.new do |parser|
        parser.banner = <<-USAGE
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

        parser.on("--server URL", "Chef server org URL (default: $CHEF_SERVER_URL)") { |v| @config.server = v }
        parser.on("--user NAME", "API user/client name (default: $CHEF_USER)") { |v| @config.user = v }
        parser.on("--key PATH", "client private key path (default: $CHEF_KEY)") { |v| @config.key = v }
        parser.on("--no-verify-ssl", "skip TLS certificate verification") { @config.verify_ssl = false }
        parser.on("-h", "--help", "show help") { puts parser; @exit_code = SUCCESS }
        parser.on("-v", "--version", "print version") { puts VERSION; @exit_code = SUCCESS }
      end
    end
  end
end
