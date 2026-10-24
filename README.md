# chefctl

A small Crystal CLI for the Chef Infra Server REST API.

## Installation

Prebuilt binaries for Linux and Windows are attached to each
[GitHub release](https://github.com/howielauvehansen94/chefctl/releases).

From source:

    shards install
    crystal build src/chefctl.cr -o bin/chefctl

On Windows this produces `bin\chefctl.exe`. Note that Crystal's Windows
support is currently a [preview](https://crystal-lang.org/install/on_windows/).

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

Pass `-F json` or `-F yaml` for machine-readable output: name lists render as
collections and `node`, `client` and `get` render as documents, e.g.

    chefctl -F yaml node web01.example.com

`--key` and `CHEF_KEY` accept `~`, which chefctl expands itself, so
`--key ~/.chef/myuser.pem` works the same in PowerShell and cmd as in POSIX
shells.

## Development

    crystal spec
