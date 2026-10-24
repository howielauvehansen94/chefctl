require "option_parser"
require "json"
require "yaml"
require "chef-auth"

module Chefctl
  VERSION = "0.2.1" # x-release-please-version

  module PrettyJSON
    def self.pretty(body : String) : String
      return "" if body.blank?

      String.build do |io|
        ::JSON.build(io, indent: "  ") { |builder| ::JSON::PullParser.new(body).read_raw(builder) }
      end
    end
  end

  module Output
    enum Format
      Json
      Yaml

      def self.parse?(value : String) : Format?
        case value
        when "json" then Json
        when "yaml" then Yaml
        end
      end
    end

    def self.body(body : String, format : Format) : String
      return "" if body.blank?

      case format
      in .json? then PrettyJSON.pretty(body)
      in .yaml? then json_to_yaml(body)
      end
    end

    def self.names(names : Array(String), format : Format) : String
      case format
      in .json? then json_names(names)
      in .yaml? then yaml_names(names)
      end
    end

    private def self.json_names(names : Array(String)) : String
      String.build do |io|
        ::JSON.build(io, indent: "  ") do |builder|
          builder.array do
            names.each { |name| builder.string(name) }
          end
        end
      end
    end

    private def self.yaml_names(names : Array(String)) : String
      String.build do |io|
        YAML.build(io) do |yaml|
          yaml.sequence do
            names.each { |name| yaml_string(name, yaml) }
          end
        end
      end
    end

    private def self.json_to_yaml(body : String) : String
      String.build do |io|
        YAML.build(io) { |yaml| walk_yaml(::JSON::PullParser.new(body), yaml) }
      end
    end

    private def self.walk_yaml(pull : ::JSON::PullParser, yaml : YAML::Builder) : Nil
      case pull.kind
      when .null?
        pull.read_next
        yaml.scalar("null", style: YAML::ScalarStyle::PLAIN)
      when .bool?
        yaml.scalar(pull.read_bool)
      when .int?
        yaml_int(pull.read_raw, yaml)
      when .float?
        yaml.scalar(pull.read_float)
      when .string?
        yaml_string(pull.read_string, yaml)
      when .begin_array?
        yaml.sequence do
          pull.read_begin_array
          until pull.kind.end_array?
            walk_yaml(pull, yaml)
          end
          pull.read_end_array
        end
      when .begin_object?
        yaml.mapping do
          pull.read_begin_object
          until pull.kind.end_object?
            yaml_string(pull.read_object_key, yaml)
            walk_yaml(pull, yaml)
          end
          pull.read_end_object
        end
      else
        raise ::JSON::ParseException.new("unexpected JSON kind: #{pull.kind}", 0, 0)
      end
    end

    private def self.yaml_string(value : String, yaml : YAML::Builder) : Nil
      if YAML::Schema::Core.reserved_string?(value)
        yaml.scalar(value, style: YAML::ScalarStyle::DOUBLE_QUOTED)
      else
        yaml.scalar(value)
      end
    end

    private def self.yaml_int(raw : String, yaml : YAML::Builder) : Nil
      if value = raw.to_i64?
        yaml.scalar(value)
      else
        yaml.scalar(raw, style: YAML::ScalarStyle::PLAIN)
      end
    end
  end

  struct Config
    property server : String?
    property user : String?
    property key : String?
    property? verify_ssl = true

    def initialize
      @server = ENV["CHEF_SERVER_URL"]?
      @user = ENV["CHEF_USER"]?
      @key = ENV["CHEF_KEY"]?
    end

    def credentials : {String, String, String}?
      if (server = @server) && (user = @user) && (key = @key)
        {server, user, Path[key].expand(home: true).to_s}
      end
    end
  end

  class CLI
    SUCCESS = 0
    FAILURE = 1

    getter parser : OptionParser

    @config = Config.new

    @format = Output::Format::Json
    @format_error : String? = nil

    @exit_code : Int32? = nil

    def initialize
      @parser = build_parser
    end

    def self.run(argv : Array(String)) : Int32
      new.run(argv)
    rescue ex : Chef::Error
      STDERR.puts ex.message
      FAILURE
    rescue ex
      STDERR.puts "error: #{ex.message || ex.class.name}"
      FAILURE
    end

    def run(argv : Array(String)) : Int32
      args = argv.dup
      begin
        parser.parse(args)
      rescue ex : OptionParser::Exception
        STDERR.puts ex.message || "invalid option"
        STDERR.puts parser
        return FAILURE
      end

      if error = @format_error
        return usage_error(error)
      end

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

    private def list_names(chef : Chef::Client, endpoint : String) : Int32
      puts Output.names(chef.get(endpoint).as_h.keys, @format)
      SUCCESS
    end

    private def show_raw(chef : Chef::Client, path : String) : Int32
      output = Output.body(chef.get_raw(path), @format)
      puts output unless output.empty?
      SUCCESS
    end

    private def with_client(&)
      credentials = @config.credentials
      unless credentials
        STDERR.puts "missing config: set --server/--user/--key or the CHEF_SERVER_URL, CHEF_USER and CHEF_KEY environment variables"
        return FAILURE
      end
      server, user, key = credentials
      yield Chef::Client.new(server, user, key, @config.verify_ssl?)
    end

    private def usage_error(message : String) : Int32
      STDERR.puts message
      FAILURE
    end

    private def set_format(value : String) : Nil
      if format = Output::Format.parse?(value)
        @format = format
      else
        @format_error = %(invalid format "#{value}", expected "json" or "yaml")
      end
    end

    private def build_parser : OptionParser
      OptionParser.new do |parser|
        parser.banner = <<-USAGE
          Usage: chefctl [flags] <command> [args]

          Commands:
            nodes          list node names
            node NAME      show a node
            clients        list client names
            client NAME    show a client
            roles          list role names
            environments   list environment names
            cookbooks      list cookbook names
            get PATH       raw GET, org-relative, e.g. "search/node?q=platform:ubuntu"
            version        print version
            help           show this help

          Flags:
          USAGE

        parser.on("--server URL", "Chef server org URL (default: CHEF_SERVER_URL env)") { |value| @config.server = value }
        parser.on("--user NAME", "API user/client name (default: CHEF_USER env)") { |value| @config.user = value }
        parser.on("--key PATH", "client private key path (default: CHEF_KEY env)") { |value| @config.key = value }
        parser.on("-F FORMAT", "--format FORMAT", "output format: json or yaml (default: json)") { |value| set_format(value) }
        parser.on("--no-verify-ssl", "skip TLS certificate verification") { @config.verify_ssl = false }
        parser.on("--verify-ssl", "verify TLS certificates (default)") { @config.verify_ssl = true }
        parser.on("-h", "--help", "show help") { puts parser; @exit_code = SUCCESS }
        parser.on("-v", "--version", "print version") { puts VERSION; @exit_code = SUCCESS }
      end
    end
  end
end

{% unless @top_level.has_constant?("Spec") %}
  exit Chefctl::CLI.run(ARGV)
{% end %}
