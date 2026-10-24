# Seeds a running Chef Infra Server (e.g. cinc-server-ng) with nodes and a
# role for chefctl integration tests. Reads CHEF_SERVER_URL, CHEF_USER and
# CHEF_KEY. Existing objects (HTTP 409) are left untouched.
require "chef-auth"

server = ENV["CHEF_SERVER_URL"]?
key = ENV["CHEF_KEY"]?
user = ENV["CHEF_USER"]? || "pivotal"

unless server && key
  abort "usage: set CHEF_SERVER_URL, CHEF_USER and CHEF_KEY (see justfile)"
end

chef = Chef::Client.new(server, user, key)

web_node = {
  "name"             => "web01.example.com",
  "chef_environment" => "_default",
  "run_list"         => ["role[webserver]"],
  "automatic"        => {"platform" => "ubuntu", "sysconf" => {"ULONG_MAX" => 18446744073709551615u64}},
  "normal"           => {"tags" => ["web"]},
}

db_node = {
  "name"             => "db01.example.com",
  "chef_environment" => "_default",
  "run_list"         => ["recipe[postgresql]"],
  "automatic"        => {"platform" => "centos"},
}

webserver_role = {
  "name"                => "webserver",
  "description"         => "web tier",
  "run_list"            => ["recipe[nginx]"],
  "default_attributes"  => {} of String => String,
  "override_attributes" => {} of String => String,
}

def create(chef : Chef::Client, path : String, body) : Nil
  chef.post(path, body)
rescue ex : Chef::Error
  raise ex unless ex.status == 409
end

create(chef, "nodes", web_node)
create(chef, "nodes", db_node)
create(chef, "roles", webserver_role)
puts "seeded 2 nodes and 1 role"
