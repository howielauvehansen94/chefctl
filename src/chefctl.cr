require "chef-auth"
require "./chefctl/cli"

exit Chefctl::CLI.run(ARGV)
