---
layout: default
title: Packaging
description: Release, native binary, and Homebrew packaging plan for Wardwright.
---

# Packaging

Status: initial Burrito/Tinfoil packaging path in place. Release `v0.1.0`
adds the Lustre workbench migration, framework-adapter recipe smokes, and local
agent-adapter install/probe support.

Wardwright is a BEAM application with a Phoenix/Lustre operator UI and Gleam
decision cores. The packaging goal is a user-facing binary that does not require
Erlang, Elixir, or Gleam on the target machine.

## Chosen Path

Wardwright uses [Burrito](https://hexdocs.pm/burrito/readme.html) to wrap the
OTP release and ERTS into a self-extracting executable. Burrito is the best fit
for the first Wardwright package because it preserves normal BEAM supervision
and Phoenix runtime behavior while removing runtime language-tool dependencies.

[Tinfoil](https://hexdocs.pm/tinfoil/readme.html) sits around Burrito for release
automation. It builds per-platform archives, creates the GitHub Release, writes
checksums, and updates the existing `bglusman/homebrew-tap` tap with a generated
`wardwright` formula.

This is intentionally separate from source development. Developers should use
`mise run check` and `mise run run:app`; users should install published release
artifacts.

## Release Targets

The configured release matrix is:

- `aarch64-apple-darwin`
- `x86_64-apple-darwin`
- `x86_64-unknown-linux-musl`
- `aarch64-unknown-linux-musl`

The first Homebrew install path should focus on macOS. Linuxbrew support can
remain best-effort until there is a real user or staging host that needs it.

## Direct Linux Install

Tinfoil also publishes plain Linux tarballs to the GitHub Release. This should
be the default non-macOS distribution path before we have a reason to introduce
Docker.

The convenience installer supports Linux x86_64 and ARM64:

```bash
curl -fsSL https://raw.githubusercontent.com/bglusman/wardwright/main/scripts/install.sh | sh
```

For a pinned release:

```bash
curl -fsSL https://raw.githubusercontent.com/bglusman/wardwright/main/scripts/install.sh | sh -s -- --version v0.1.0
```

The script downloads the matching release archive, requires
`checksums-sha256.txt`, verifies the archive checksum, and installs `wardwright`
to `~/.local/bin` by default. A manual install is equivalent:

```bash
curl -fLO https://github.com/bglusman/wardwright/releases/download/v0.0.10/wardwright-0.0.10-x86_64-unknown-linux-musl.tar.gz
curl -fLO https://github.com/bglusman/wardwright/releases/download/v0.0.10/checksums-sha256.txt
sha256sum -c checksums-sha256.txt --ignore-missing
tar -xzf wardwright-0.0.10-x86_64-unknown-linux-musl.tar.gz
install -m 0755 wardwright ~/.local/bin/wardwright
```

The Linux binary has the same runtime contract as the Homebrew package: set a
stable `WARDWRIGHT_SECRET_KEY_BASE`, optionally set `WARDWRIGHT_ADMIN_TOKEN`,
and run the binary as the local HTTP service. Systemd packaging can be added
later without changing the release artifact shape.

## Local Planning

From `app/`:

```bash
mise exec -- mix tinfoil.plan
```

The plan should show a GitHub release for `bglusman/wardwright` and Homebrew tap
updates for `bglusman/homebrew-tap`.

To build locally on macOS, install Burrito's build prerequisites. Burrito
currently expects Zig 0.15.2. On macOS 26 / Xcode 26, use Homebrew's patched
`zig@0.15` formula rather than the upstream Zig archive:

```bash
brew install zig@0.15
WARDWRIGHT_SECRET_KEY_BASE="$(openssl rand -base64 64)" mise run package:build:darwin-arm64
```

Linux builds can use the upstream Zig 0.15.2 archive. Windows targets also need
`7z`, but Wardwright does not currently publish a Windows package.

The output binary lands in `app/burrito_out/`. Tinfoil's CI workflow wraps
per-target binaries into versioned release archives under `_tinfoil/`.

## Homebrew

The release workflow updates the existing tap. Install on macOS with:

```bash
brew tap bglusman/tap
brew install wardwright
wardwright admin
```

The generated formula:

- installs the Burrito-wrapped `wardwright` binary;
- creates `etc/wardwright`, `var/lib/wardwright`, and `var/log/wardwright`;
- generates `etc/wardwright/secret_key_base` on first install;
- runs Wardwright bound to `127.0.0.1:8787` under `brew services` by default;
- reads the service bind from `etc/wardwright/bind`, which defaults to
  `127.0.0.1:8787`; change that file before starting the service, or restart
  the service after changing it, to use a different port;
- does not require Erlang, Elixir, or Gleam at runtime.

The same installed binary also exposes small operator/agent helper commands:

```bash
wardwright --help
wardwright serve
wardwright admin
wardwright admin access
wardwright tools
wardwright tools --json
```

`wardwright admin` opens the operator workbench in the default browser. If the
configured bind port is not responding, it starts `wardwright serve` in the
background first. `wardwright admin access` opens Models & access
directly. Homebrew users can still run Wardwright as a service with
`brew services start wardwright`; the admin helper just removes the need to
remember the local URL.

`wardwright tools` prints MCP and policy-authoring API instructions for local
agents. The JSON form is generated from the same registry used by the protected
`/v1/policy-authoring/tools` endpoint, so scripts can discover the available
authoring surface without scraping the UI. The advertised HTTP surface includes
draft model creation, local model activation, draft-only rule-change proposals,
validation, projection explanation, simulation, Dune snippet, and scenario
record/import/export/retention tools. The MCP endpoint currently exposes the
projection, simulation, Dune snippet, draft/activate/propose, and validation
subset; scenario write tools remain HTTP-only. The
[Agent Authoring Guide](agent-authoring.html) explains when an agent should use
each tool and which operations are draft-only versus write-capable.

The experimental in-page authoring assistant is intentionally disabled unless
configured. Service installs should put its settings in
`/opt/homebrew/etc/wardwright/authoring_agent.env` on Apple Silicon Homebrew,
`/usr/local/etc/wardwright/authoring_agent.env` on Intel Homebrew, or
`~/.config/wardwright/authoring_agent.env` for user-local runs. Use
`WARDWRIGHT_AUTHORING_AGENT_CONFIG_FILE` to point at a different file. This
keeps `brew services` and `wardwright admin` launches from silently losing the
local model/provider selection that was only present in one shell session.

`WARDWRIGHT_ADMIN_TOKEN` remains optional for loopback-only use. For browser
access to the operator workbench and protected control APIs beyond loopback, set
`BASIC_AUTH_PASSWORD`; the Basic Auth username is always `admin`. This protects
operator surfaces such as `/admin`, `/mcp`, `/admin/*`, receipts, and
policy-authoring and simulation APIs. OpenAI-compatible model
endpoints remain governed by model access configuration. Generated model API
keys and the active model definition are stored in the SQLite database at
`~/.local/share/wardwright/wardwright.sqlite3` unless `XDG_DATA_HOME` or
`WARDWRIGHT_SQLITE_STORE` points somewhere else. Keep
`WARDWRIGHT_SECRET_KEY_BASE` stable, or set
`WARDWRIGHT_MODEL_API_KEY_HASH_SECRET` explicitly, so stored keys remain
verifiable across restarts. To encrypt the store, set `WARDWRIGHT_SQLITE_KEY` or
`WARDWRIGHT_SQLITE_KEY_FNOX` and ship an exqlite build linked against SQLCipher;
Wardwright checks `PRAGMA cipher_version` and refuses to start with a configured
key when SQLCipher is unavailable. For foreground testing without `brew services`, run:

```bash
WARDWRIGHT_SECRET_KEY_BASE="$(cat "$(brew --prefix)/etc/wardwright/secret_key_base")" \
WARDWRIGHT_BIND=127.0.0.1:8787 \
wardwright serve
```

### SQLite Encryption in Packaged Builds

exqlite can link its NIF against SQLCipher by setting `EXQLITE_USE_SYSTEM=1`,
`EXQLITE_SYSTEM_CFLAGS`, and `EXQLITE_SYSTEM_LDFLAGS` during compilation.
Burrito can rebuild NIFs per target with `:nif_env`/`:nif_cflags` qualifiers,
and Tinfoil will package the resulting Burrito binaries. That means encrypted
SQLite can be made available in packaged builds, but it must be solved in the
release build matrix, not at runtime.

The conservative release path is:

1. install or vendor SQLCipher headers and libraries for each target;
2. compile exqlite with `EXQLITE_USE_SYSTEM=1` and SQLCipher include/linker
   flags;
3. run a packaged-binary smoke test with `WARDWRIGHT_SQLITE_KEY` set and assert
   the app starts and `PRAGMA cipher_version` is present.

Until that matrix is wired, `WARDWRIGHT_SQLITE_KEY` and
`WARDWRIGHT_SQLITE_KEY_FNOX` are opt-in and fail closed when the binary was not
built with SQLCipher.

## Provider Credentials

The package does not install fnox. If a configured provider target uses
`credential_fnox_key`, the host running Wardwright must already have a working
`fnox` command on `PATH`; Wardwright resolves the value with `fnox get KEY` when
it needs to call the provider. Environment-variable credentials via
`credential_env` are also supported for local development and live smoke tests.
Database-backed provider credentials should wait until SQLCipher-enabled
packaged builds are part of the release matrix. Once encrypted SQLite is
guaranteed, Wardwright can remove fnox as a required secret-store dependency by
storing provider credentials in the same encrypted local database and failing
closed whenever credentials are configured but the database is not encrypted.

Credential storage and service authentication are separate. Fnox keeps raw
provider keys out of artifacts and logs, but it does not decide who may call a
Wardwright model. Do not configure real provider credentials on a Wardwright
instance reachable by untrusted users unless the service is bound behind a
trusted authentication boundary. See [Provider Credentials](provider-credentials.html).

## Release Workflow

The root workflow `.github/workflows/wardwright-release.yml` is adapted from
Tinfoil's generated workflow because this repository keeps the Mix app under
`app/`.

Tagging a stable `v*` release should:

1. Build Burrito binaries for each configured target.
2. Upload archives and checksums to a GitHub Release.
3. Publish provenance attestations.
4. Update `Formula/wardwright.rb` in `bglusman/homebrew-tap` for stable tags.

The Homebrew update job needs a `HOMEBREW_TAP_TOKEN` repository secret with
write access to `bglusman/homebrew-tap`. Tinfoil also supports deploy-key auth,
which is preferable once release automation is no longer experimental.

Dev tags such as `v0.1.0-dev` are published as GitHub prereleases but do not
update the Homebrew tap. The `v0.1.0` stable tag updates the tap after release
artifacts and checksums publish successfully.

## Known Gaps

- Release `v0.0.1` was cut, but its packaged payload missed the Gleam decision
  core modules and should be superseded by `v0.0.2`.
- Release `v0.0.2` was the first usable packaging baseline.
- Release `v0.0.3` adds initial policy visualization, simulation playback, and
  the recipe catalog workbench boundary.
- Release `v0.0.4` adds clearer model binding visibility in the state-machine
  workbench, seeded example collections, simulator screenshots/docs, and
  prepares the next package version.
- Release `v0.0.5` adds workspace Dune snippet save/evaluate/compose/delete
  support for local agents and a Homebrew service bind file for port overrides.
- Release `v0.0.8` adds simulation-target selection, editable retry attempts,
  saved simulator test cases, screenshots/docs for the stronger simulator loop,
  a legacy experimental in-page authoring assistant, Tidewave-assisted
  development setup, and Credo/Quokka/browser ratchets.
- Release `v0.0.10` preserves the unified `/admin` workbench shell from
  `v0.0.9` and fixes packaged releases so the Gleam/Lustre runtime modules are
  included in the Burrito payload.
- Release `v0.1.0` adds the Lustre workbench migration, framework-adapter
  recipe foundation, and local agent-adapter install/probe lifecycle. It does
  not imply exact cross-agent replay or native framework state fidelity. It also
  adds a Wardwright-hosted server-tool framework with one registered read-only
  built-in, `wardwright_policy_cache_status`, trusted Dune function tools, and
  trusted BEAM module tools loaded from explicit `.ex/.exs`, `.erl`, or `.beam`
  paths. Receipts record explicit engine, execution-location, visibility, status,
  and result metadata; these extension tools are trusted local operator code,
  not a sandbox or side-effect approval system.
- Fnox-backed provider credentials are runtime-supported but not package-managed;
  fnox installation/profile management and product authorization remain
  hardening work beyond this release.
- The first CI run may expose platform-specific Burrito, Zig, or NIF issues.
  macOS builds intentionally install Homebrew `zig@0.15` because upstream Zig
  0.15.2 can fail to link on newer macOS/Xcode combinations.
- Burrito prints some wrapper diagnostics to stderr before the BEAM app starts.
- The current app has minimal static assets. If Phoenix/Lustre assets grow
  beyond the checked-in bundle, packaging must add an explicit asset
  build/digest step before `mix release`.
