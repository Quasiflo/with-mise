#!/usr/bin/env bash
#* Full CI Mise setup
# Required env vars:
#   SCRIPT_SUBCOMMAND — The operation this script should execute
#*  Allowed Options: SETUP, INSTALL_TOOLS

set -euo pipefail

: "${CI_PLATFORM:?CI_PLATFORM is not set}"
: "${SCRIPT_SUBCOMMAND:?SCRIPT_SUBCOMMAND is not set}"

#! General Functions
is_truthy() {
	local val
	val=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
	case "$val" in
	true | 1 | yes | on) return 0 ;;
	*) return 1 ;;
	esac
}

# Usage: has_value VAR_VALUE
# True when the value contains something other than whitespace/commas. Tool lists like "" or " , ," count as empty.
has_value() {
	local v
	v=$(printf '%s' "${1-}" | tr -d '[:space:],')
	[ -n "$v" ]
}

# Usage: normalize_tools LIST
# Trims whitespace, drops empty entries, strips optional core: prefixes
# (e.g. core:node -> node). NOTE: pass full tool IDs as in mise.toml
# (e.g. aqua:jdx/hk) — short names do not match non-core tools.
normalize_tools() {
	printf '%s' "${1-}" |
		tr ',' '\n' |
		sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/^core://' |
		grep -v '^$' |
		paste -sd ',' - |
		sed -e 's/^,*//' -e 's/,*$//'
}

# Portable sha256 helpers (sha256sum is Linux-only; macOS has shasum/openssl).
sha256_stdin() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 | cut -d' ' -f1
	else
		openssl dgst -sha256 -r | cut -d' ' -f1
	fi
}

sha256_file() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$1" | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 "$1" | cut -d' ' -f1
	else
		openssl dgst -sha256 -r "$1" | cut -d' ' -f1
	fi
}

# Usage: prepend_path DIR
# Prepends DIR to PATH in the current shell AND in all subsequent steps, without snapshotting the full PATH value.
prepend_path() {
	local new_dir="$1"
	export PATH="$new_dir:$PATH" # current shell
	if [ "$CI_PLATFORM" = "circleci" ]; then
		# shellcheck disable=SC2016 # BASH_ENV is sourced as a script — $PATH defers to each step's live value
		printf 'export PATH="%s:$PATH"\n' "$new_dir" >>"${BASH_ENV:?BASH_ENV is not set}"
	elif [ "$CI_PLATFORM" = "github_actions" ]; then
		# GITHUB_PATH prepends to the live PATH at the start of each step
		echo "$new_dir" >>"${GITHUB_PATH:?GITHUB_PATH is not set}"
	fi
}

# Usage: persist_env VAR_NAME [value]
# Writes a variable into the CI-platform env file so it's available in later steps/jobs.
persist_env() {
	local var_name="$1"
	local var_value

	if [ $# -ge 2 ]; then
		var_value="$2"
	else
		var_value="${!var_name}"
	fi

	if [ "$CI_PLATFORM" = "circleci" ]; then
		# BASH_ENV is sourced as a shell script — use %q so quotes/$/`/!/newlines survive. shellcheck disable=SC2059
		printf 'export %s=%q\n' "$var_name" "$var_value" >>"${BASH_ENV:?BASH_ENV is not set}"
	elif [ "$CI_PLATFORM" = "github_actions" ]; then
		# GITHUB_ENV uses a key=value format. Use a unique heredoc delimiter so values containing newlines (e.g. tool lists) can't collide/inject.
		local delim="__WITH_MISE_EOF_${$}_${RANDOM}__"
		{
			echo "${var_name}<<${delim}"
			echo "$var_value"
			echo "${delim}"
		} >>"${GITHUB_ENV:?GITHUB_ENV is not set}"
	else
		echo "Error: Unknown CI_PLATFORM: '$CI_PLATFORM'" >&2
		return 1
	fi
}

mise_config_hash() {
	if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
		echo "Error: not inside a git work tree (actions/checkout required for cache keys)" >&2
		printf 'no-git-checkout'
		return 0
	fi
	local files
	files=$(
		git ls-files -z \
			':(glob,icase)**/.tool-versions' \
			':(glob,icase)**/mise.toml' \
			':(glob,icase)**/mise.lock' \
			':(glob,icase)**/mise.*.toml' \
			':(glob,icase)**/mise.*.lock' \
			':(glob,icase)**/.mise.toml' \
			':(glob,icase)**/.mise.lock' \
			':(glob,icase)**/.mise.*.toml' \
			':(glob,icase)**/.mise.*.lock' \
			':(glob,icase)**/mise/config.toml' \
			':(glob,icase)**/mise/config.lock' \
			':(glob,icase)**/mise/config.*.toml' \
			':(glob,icase)**/mise/config.*.lock' \
			':(glob,icase)**/.mise/config.toml' \
			':(glob,icase)**/.mise/config.lock' \
			':(glob,icase)**/.mise/config.*.toml' \
			':(glob,icase)**/.mise/config.*.lock' \
			':(glob,icase)**/.config/mise.toml' \
			':(glob,icase)**/.config/mise.lock' \
			':(glob,icase)**/.config/mise.*.toml' \
			':(glob,icase)**/.config/mise.*.lock' \
			':(glob,icase)**/.config/mise/config.toml' \
			':(glob,icase)**/.config/mise/config.lock' \
			':(glob,icase)**/.config/mise/config.*.toml' \
			':(glob,icase)**/.config/mise/config.*.lock' |
			tr '\0' '\n' |
			sort -u
	)
	if [ -z "$files" ]; then
		printf 'no-mise-files'
		return 0
	fi
	printf '%s\n' "$files" |
		while IFS= read -r f; do
			[ -f "$f" ] || continue
			sha256_file "$f"
		done |
		sha256_stdin
}

#! Subcommand Functions
run_setup() {
	#* --- Normalize optional env vars (defensive under `set -u`) ---
	# USE_TOOLS/EXCLUDE_TOOLS default to "" (= all tools enabled). STRICT_MODE defaults to "true". Empty/unset are valid; only non-empty values in both tool lists are mutually exclusive.
	STRICT_MODE="${STRICT_MODE:-true}"
	USE_TOOLS="${USE_TOOLS:-}"
	EXCLUDE_TOOLS="${EXCLUDE_TOOLS:-}"
	if has_value "${USE_TOOLS:-}" && has_value "${EXCLUDE_TOOLS:-}"; then
		echo "USE_TOOLS & EXCLUDE_TOOLS are mutually exclusive! Choose one!"
		exit 1
	fi

	#* Install Mise & Setup
	# MISE_LOCKED=1 is equivalent to `mise install --locked` (see mise docs); persisting it is enough — INSTALL_TOOLS needs no explicit flag.
	if is_truthy "$STRICT_MODE"; then
		export MISE_LOCKED=1
		persist_env MISE_LOCKED
	fi
	export MISE_YES=1
	export MISE_AUTO_INSTALL=false
	persist_env MISE_YES
	persist_env MISE_AUTO_INSTALL

	# Always create the temp dir up-front so cleanup runs on every platform.
	WITH_MISE_TMP_DIR="$(mktemp -d)"
	# shellcheck disable=SC2064 # intentional: expand now, clean the same dir on EXIT
	trap "rm -rf \"${WITH_MISE_TMP_DIR:?}\"" EXIT INT TERM

	if [[ "$(uname)" == "Darwin" ]]; then
		# install.sh verifies the downloaded tarball checksum internally (get_checksum + shasum check for macos targets); GPG would need brew gnupg on stock macOS images, so checksum is the practical check.
		curl -fsSL https://mise.run | sh
	else
		#* Install Mise & verify against known key
		if ! command -v gpg >/dev/null 2>&1; then
			echo "Error: gpg is required for Linux mise install verification" >&2
			exit 1
		fi
		gpg --batch --keyserver hkps://keys.openpgp.org --recv-keys 24853EC9F655CE80B48E6C3A8B81C9D17413A06D
		curl -fsSL https://mise.en.dev/install.sh.sig -o "$WITH_MISE_TMP_DIR/install.sh.sig"
		gpg --batch --decrypt "$WITH_MISE_TMP_DIR/install.sh.sig" >"$WITH_MISE_TMP_DIR/install.sh"
		sh "$WITH_MISE_TMP_DIR/install.sh"
	fi

	prepend_path "$HOME/.local/bin" # This is where mise binary is installed

	eval "$(mise activate bash --shims)" # Activate shims so tools are available in this script
	mise trust "$PWD"                    # Trust only the workspace checkout, not every config on the runner

	#* Set Envs
	# mise semantics (verified): MISE_ENABLE_TOOLS unset = all enabled;
	# MISE_ENABLE_TOOLS="" = all disabled. So default/exclude must UNSET enable and use MISE_DISABLE_TOOLS for exclusions.
	if has_value "${USE_TOOLS:-}"; then
		MISE_ENABLE_TOOLS="$(normalize_tools "${USE_TOOLS:-}")"
		export MISE_ENABLE_TOOLS
		unset MISE_DISABLE_TOOLS || true
		persist_env MISE_ENABLE_TOOLS
	elif has_value "${EXCLUDE_TOOLS:-}"; then
		unset MISE_ENABLE_TOOLS || true
		MISE_DISABLE_TOOLS="$(normalize_tools "${EXCLUDE_TOOLS:-}")"
		export MISE_DISABLE_TOOLS
		persist_env MISE_DISABLE_TOOLS
	else
		unset MISE_ENABLE_TOOLS || true
		unset MISE_DISABLE_TOOLS || true
	fi
	# Resultant active tool names (not versions) straight from mise, so adding
	# or removing tools in mise.toml changes the cache key even when the
	# use/exclude filters are empty. Versions are covered by FILES_CHECKSUM.
	# Falls back to hashing the filter selection if listing fails.
	if ACTIVE_TOOLS=$(mise ls --current --no-header 2>/dev/null | awk '{print $1}' | sort -u); then
		if has_value "${USE_TOOLS:-}" && [ -z "$ACTIVE_TOOLS" ]; then
			echo "Error: USE_TOOLS matched no tools. Use full tool IDs as in mise.toml (e.g. aqua:jdx/hk,node) — short names do not match non-core tools." >&2
			exit 1
		fi
		TOOLS_CHECKSUM=$(printf '%s' "$ACTIVE_TOOLS" | sha256_stdin | cut -c1-16)
	else
		TOOLS_CHECKSUM=$(printf '%s|%s' "${MISE_ENABLE_TOOLS-}" "${MISE_DISABLE_TOOLS-}" | sha256_stdin | cut -c1-16)
	fi
	FILES_CHECKSUM=$(mise_config_hash)
	#* Save into files for CI not supporting env for cache keys
	mkdir -p tmp
	echo "$TOOLS_CHECKSUM" >tmp/TOOLS_CHECKSUM.txt
	echo "$FILES_CHECKSUM" >tmp/FILES_CHECKSUM.txt
	persist_env TOOLS_CHECKSUM
	persist_env FILES_CHECKSUM
	# Only persist allow/deny lists when set: MISE_ENABLE_TOOLS="" would disable ALL tools, and unset vars fail under `set -u`.
	if [ -n "${MISE_ENABLE_TOOLS-}" ]; then
		persist_env MISE_ENABLE_TOOLS
	fi
	if [ -n "${MISE_DISABLE_TOOLS-}" ]; then
		persist_env MISE_DISABLE_TOOLS
	fi
}

run_install_tools() {
	#* Install mise tools
	# MISE_LOCKED (persisted in SETUP) already enforces --locked behavior.
	echo "Currently Enabled Tools: ${MISE_ENABLE_TOOLS-<all>}"
	echo "Currently Disabled Tools: ${MISE_DISABLE_TOOLS-<none>}"
	mise install
	mise reshim -f # Reshim to ensure all shims are valid after potential cache restore
}

case "$SCRIPT_SUBCOMMAND" in
SETUP) run_setup ;;
INSTALL_TOOLS) run_install_tools ;;
*)
	echo "Unsupported Script Subcommand: $SCRIPT_SUBCOMMAND"
	exit 1
	;;
esac
