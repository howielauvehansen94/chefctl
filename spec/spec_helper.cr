require "spec"
# src/chefctl.cr calls exit at require time, so require the CLI directly.
require "../src/chefctl/cli"
