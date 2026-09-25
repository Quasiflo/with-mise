# Orb Source

Unpacked orb source (packed with `circleci orb pack src/`). See the root [README.md](../README.md) for usage.

- `@orb.yml` — orb header (`version`, `description`, `display`).
- `commands/run_task.yml` — installs mise tools via `<<include(scripts/everything.sh)>>` and runs `commands`.
- `jobs/run_task.yml` — `checkout` + `run_task` command wrapper with optional `skip`.
- `scripts/everything.sh` — canonical CI logic (also vendored to `.github/actions/run_task/everything.sh` via `src/scripts/sync-action.sh`).
- `examples/example.yml` — minimal `run_task` example.
