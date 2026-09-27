# chefctl

A small Crystal CLI for the Chef Infra Server REST API.

## Installation

    shards install
    crystal build src/chefctl.cr -o bin/chefctl

## Usage

    export CHEF_SERVER_URL=https://chef.example.com/organizations/myorg
    export CHEF_USER=myuser
    export CHEF_KEY="$HOME/.chef/myuser.pem"

    chefctl nodes
    chefctl node web01.example.com
    chefctl get "search/node?q=platform:ubuntu"

Run `chefctl --help` for all commands and flags. The `get` command hits any
org-relative endpoint, so search, data bags (`get data`), etc. work without
dedicated commands.

## Development

    crystal spec
