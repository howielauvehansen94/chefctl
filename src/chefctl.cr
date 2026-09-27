require "./utils/chef_api"
require "./chefctl/cli"

exit Chefctl::CLI.run(ARGV)
