# Integration tests for chefctl against cinc-server-ng, an in-memory
# implementation of the Chef Infra Server API.
#
# The container runtime is auto-detected (docker first, podman as fallback).
# Override with: just CONTAINER_RUNTIME=podman integration

image       := "ghcr.io/cinc-project/cinc-server-ng:latest"
container   := "chefctl-cinc-server"
org         := "test"
admin_user  := "pivotal"
port        := env_var_or_default("CINC_PORT", "8889")
key_dir     := "/tmp/chefctl-cinc"
server_url  := "http://localhost:" + port + "/organizations/" + org
detected    := `if command -v docker >/dev/null 2>&1; then echo docker; elif command -v podman >/dev/null 2>&1; then echo podman; else echo docker; fi`
runtime     := env_var_or_default("CONTAINER_RUNTIME", detected)

default:
    @just --list

build:
    crystal build src/chefctl.cr -o bin/chefctl

# Start cinc-server-ng and export the pivotal admin key
server-up:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! command -v {{ runtime }} >/dev/null 2>&1; then
        echo "error: container runtime '{{ runtime }}' not found; install docker or podman (or set CONTAINER_RUNTIME)" >&2
        exit 1
    fi
    mkdir -p {{ key_dir }}
    chmod 777 {{ key_dir }}
    {{ runtime }} rm -f {{ container }} >/dev/null 2>&1 || true
    {{ runtime }} run -d --name {{ container }} -p {{ port }}:8889 -v {{ key_dir }}:/keys {{ image }} \
        --addr 0.0.0.0:8889 --orgs {{ org }} --key-out /keys/admin.pem >/dev/null
    for _ in $(seq 1 60); do
        curl -sf http://localhost:{{ port }}/_status >/dev/null 2>&1 && break
        sleep 0.5
    done
    if ! curl -sf http://localhost:{{ port }}/_status >/dev/null; then
        echo "error: cinc-server-ng did not become healthy" >&2
        {{ runtime }} logs {{ container }} >&2
        exit 1
    fi
    {{ runtime }} cp {{ container }}:/keys/admin.pem - | tar -xOf - > {{ key_dir }}/pivotal.pem
    chmod 600 {{ key_dir }}/pivotal.pem
    echo "cinc-server-ng ready on {{ server_url }}"
    echo "credentials: {{ admin_user }} / {{ key_dir }}/pivotal.pem"

# Remove the test server
server-down:
    {{ runtime }} rm -f {{ container }} >/dev/null 2>&1 || true

# Seed the running server with nodes and a role
seed:
    #!/usr/bin/env bash
    set -euo pipefail
    export CHEF_SERVER_URL="{{ server_url }}" CHEF_USER={{ admin_user }} CHEF_KEY="{{ key_dir }}/pivotal.pem"
    crystal run scripts/seed-server.cr

# Print exports for talking to the test server; use as: eval "$(just create-env)"
create-env:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! curl -sf http://localhost:{{ port }}/_status >/dev/null 2>&1; then
        just server-up >/dev/null
    elif [[ ! -s {{ key_dir }}/pivotal.pem ]]; then
        {{ runtime }} cp {{ container }}:/keys/admin.pem - | tar -xOf - > {{ key_dir }}/pivotal.pem
        chmod 600 {{ key_dir }}/pivotal.pem
    fi
    echo "export CHEF_SERVER_URL={{ server_url }}"
    echo "export CHEF_USER={{ admin_user }}"
    echo "export CHEF_KEY={{ key_dir }}/pivotal.pem"
    echo "hint: run 'just server-down' when finished" >&2

# Run the full integration suite: build, boot the server, seed, assert, tear down
integration: build
    #!/usr/bin/env bash
    set -euo pipefail
    export CHEF_SERVER_URL="{{ server_url }}" CHEF_USER={{ admin_user }} CHEF_KEY="{{ key_dir }}/pivotal.pem"
    BIN=bin/chefctl
    runtime={{ runtime }}

    teardown() { "$runtime" rm -f {{ container }} >/dev/null 2>&1 || true; }
    trap teardown EXIT

    just server-up >/dev/null

    check() {
        local label=$1 expected=$2 actual=$3
        if [[ $actual == *"$expected"* ]]; then
            echo "ok: $label"
        else
            echo "FAIL: $label" >&2
            echo "  wanted: $expected" >&2
            echo "  got:    $actual" >&2
            exit 1
        fi
    }

    check "empty node list renders as a JSON array" "[]" "$("$BIN" nodes)"
    crystal run scripts/seed-server.cr >/dev/null

    check "node list (json)" "web01.example.com" "$("$BIN" nodes)"
    check "node list (yaml)" "- web01.example.com" "$("$BIN" -F yaml nodes)"
    check "node yaml keeps values beyond Int64" "ULONG_MAX: 18446744073709551615" "$("$BIN" -F yaml node web01.example.com)"
    check "node json keeps values beyond Int64" '"ULONG_MAX": 18446744073709551615' "$("$BIN" node web01.example.com)"
    check "roles list" "webserver" "$("$BIN" roles)"
    check "search (yaml)" "total: 1" "$("$BIN" -F yaml get "search/node?q=platform:ubuntu")"
    check "environment (yaml)" "The default Chef environment" "$("$BIN" -F yaml get environments/_default)"

    if "$BIN" -F xml nodes >/dev/null 2>&1; then
        echo "FAIL: -F xml should be rejected" >&2
        exit 1
    fi
    echo "ok: invalid format rejected"

    if CHEF_USER=impostor "$BIN" nodes >/dev/null 2>&1; then
        echo "FAIL: bad credentials should fail" >&2
        exit 1
    fi
    echo "ok: bad credentials rejected"

    echo "integration: all checks passed"
