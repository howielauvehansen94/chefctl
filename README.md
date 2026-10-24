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

    chefctl get nodes
    chefctl get node web01.example.com
    chefctl create node web01.example.com
    chefctl get "search/node?q=platform:ubuntu"

Run `chefctl --help` for all commands and flags. The `get` command also hits
any org-relative endpoint (a PATH containing `/` or `?`), so search, data bags
(`get data`), etc. work without dedicated commands.

Objects are created and updated from JSON passed with `--file FILE` (`-`
reads stdin) or piped on stdin; `create node` generates a minimal empty node
when no body is given:

    chefctl get node web01.example.com > web01.json
    $EDITOR web01.json
    chefctl update node web01.example.com --file web01.json
    chefctl delete node web01.example.com

Pass `-F json` or `-F yaml` for machine-readable output: name lists render as
collections and everything else renders as documents, e.g.

    chefctl -F yaml get node web01.example.com

`--key` and `CHEF_KEY` accept `~`, which chefctl expands itself, so
`--key ~/.chef/myuser.pem` works the same in PowerShell and cmd as in POSIX
shells.

## Development

    crystal spec

Integration tests boot [cinc-server-ng](https://github.com/cinc-project/cinc-server-ng)
(an in-memory Chef Infra Server implementation) in a container and run the CLI
against it. Requires docker or podman (docker is the default) plus `just`:

    just integration

The suite tears the server down afterwards; `eval "$(just create-env)"` starts
the server (if needed) and exports `CHEF_SERVER_URL`, `CHEF_USER` and
`CHEF_KEY` into your shell for manual `chefctl` runs — `just server-down`
cleans up. `just server-up`, `just seed` and `just server-down` are available
for lower-level control, and `CONTAINER_RUNTIME=podman just integration`
forces podman.
