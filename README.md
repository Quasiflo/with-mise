# With-Mise

<!-- Badges commented out until first orb publish (lychee 404s pre-publish). Uncomment after v1.
[![CircleCI Build Status](https://circleci.com/gh/Quasiflo/with-mise.svg?style=shield "CircleCI Build Status")](https://circleci.com/gh/Quasiflo/with-mise) [![CircleCI Orb Version](https://badges.circleci.com/orbs/quasiflo/with-mise.svg)](https://circleci.com/developer/orbs/orb/quasiflo/with-mise) [![GitHub License](https://img.shields.io/badge/license-Apache--2.0-lightgrey.svg)](https://raw.githubusercontent.com/Quasiflo/with-mise/main/LICENSE) [![CircleCI Community](https://img.shields.io/badge/community-CircleCI%20Discuss-343434.svg)](https://discuss.circleci.com/c/ecosystem/orbs)
-->

CI/CD glue for jobs using Mise-installed tools. Ships as both a CircleCI orb (`with-mise/run_task`) and a GitHub composite Action (`.github/actions/run_task`), sharing one script: `src/scripts/everything.sh`.

What it does per run:

1. Installs `mise` (Linux: GPG-verified install script; macOS: `curl -fsSL` install script with built-in checksum validation).
2. Activates shims, trusts the workspace checkout, sets `MISE_LOCKED=1` when `strict_mode` is on (equivalent to `mise install --locked`).
3. Optionally restores/saves a `mise` tool cache, runs `mise install`, then runs your `commands`.

## Usage

### CircleCI

```yaml
version: 2.1
orbs:
  with-mise: quasiflo/with-mise@0.1.0 # x-release-please-version
executors:
  linux:
    docker:
      - image: cimg/base:current
workflows:
  build:
    jobs:
      - with-mise/run_task:
          executor: linux
          commands: templatry generate && hk check --all
```

### GitHub Actions

Downstream consumers in other repos use a pinned ref to use reusable action. Checkout is required first — your `mise.toml`, lockfiles, and commands live in the workspace:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false
      - uses: Quasiflo/with-mise/.github/actions/run_task@v0.1.0 # x-release-please-version
        with:
          commands: mise run build
```

## Inputs

| Input | Type | Default | Description |
| --- | --- | --- | --- |
| `commands` | string | (required) | Commands to run after `mise install` |
| `strict_mode` | bool | `true` | Sets `MISE_LOCKED=1` (fail if lockfile lacks URLs for this platform; equivalent to `--locked`) |
| `use_cache` | bool | `false` | Cache `~/.local/share/mise` keyed on tool selection + mise config hash |
| `use_tools` | string | `""` | Comma-separated allowlist of full mise tool IDs (as in `mise.toml`, e.g. `aqua:jdx/hk,node`; short names do not match non-core tools). Sets `MISE_ENABLE_TOOLS`. Mutually exclusive with `exclude_tools` |
| `exclude_tools` | string | `""` | Comma-separated denylist of full mise tool IDs (as in `mise.toml`, e.g. `aqua:jdx/hk`). Sets `MISE_DISABLE_TOOLS`. Mutually exclusive with `use_tools` |

Empty `use_tools`/`exclude_tools` means all tools enabled. Note: `MISE_ENABLE_TOOLS=""` would disable everything, so the script unsets (rather than empties) the var in default/exclude modes.

## Requirements & Platform Notes

- Linux and macOS are supported (`cimg/base`, `ubuntu-2204` machine, macOS Xcode, `ubuntu-slim`). Windows works only via Git Bash and is experimental, not tested in CI.
- `ubuntu-slim` is a 1-CPU container image with minimal tools — fine for lint, potentially slow for heavy `mise install` sets. Use `ubuntu-latest` for heavy builds.
- Cache keys use `tmp/TOOLS_CHECKSUM.txt` + `tmp/FILES_CHECKSUM.txt` (CircleCI) or `env.TOOLS/FILES_CHECKSUM` (GitHub). `mise_config_hash` requires a git checkout; without one it records `no-git-checkout`.
- Scripts are POSIX-portable across Linux/macOS: `sha256sum` → `shasum -a 256` → `openssl` fallback, `curl -fsSL` everywhere, `mktemp -d` + `EXIT/INT/TERM` trap cleanup on all platforms.

## Development

```sh
templatry generate && hk check --all
```

Source of truth for CI logic is `src/scripts/everything.sh`. The GitHub Action runs a vendored copy at `.github/actions/run_task/everything.sh` (via `$ACTION_PATH`, so no checkout is needed to load the action). Keep them in sync:

```sh
src/scripts/sync-action.sh
```

`hk fix`/`hk check --all` enforce this — drift fails the build.

Orb packing (CircleCI `<<include(scripts/everything.sh)>>` inlines at pack time):

```sh
circleci orb pack src/ > orb.yml
circleci orb validate orb.yml
```

## Resources

[CircleCI Orb Registry Page](https://circleci.com/developer/orbs/orb/quasiflo/with-mise) - The official registry page of this orb for all versions, executors, commands, and jobs described.

[CircleCI Orb Docs](https://circleci.com/docs/orb-intro/#section=configuration) - Docs for using, creating, and publishing CircleCI Orbs.

### How to Contribute

We welcome [issues](https://github.com/Quasiflo/with-mise/issues) to and [pull requests](https://github.com/Quasiflo/with-mise/pulls) against this repository!

## License

This repository is licensed under the Apache License 2.0.

- **Copyright (c) 2026 Quasiflo**
- **Permission Granted:** You are free to use, copy, modify, distribute, and sublicense this software, including for commercial purposes, subject to the terms of the license.
- **Conditions:** You must include the original copyright notice and a copy of the license in any distribution, clearly state any significant changes made to the original files, and retain any attribution notices from a NOTICE file (if present).
- **Patent Grant:** Contributors grant a patent license covering their contributions. This patent license terminates if you institute patent litigation alleging that the Work (or a Contribution) infringes a patent.
- **No Warranty:** This software is provided "as is," without warranties or conditions of any kind, express or implied.

See the [LICENSE](LICENSE) file for the full legal text.
