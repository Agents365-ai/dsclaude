#!/usr/bin/env bash
# lib/common.sh — shared functions sourced by all *claude launcher scripts.
# This file is not meant to be executed directly.
#
# Each launcher must set this variable before sourcing this file:
#   SELF_DIR       — absolute path to the directory containing the launcher script
#
# Before calling export_anthropic_base the launcher must set:
#   BASE_URL, API_KEY, MAIN_MODEL, FLASH_MODEL

# ---- find_repo: locate the xxclaude repository checkout -----------------
# Usage: repo="$(find_repo "DSCLAUDE_HOME")"
find_repo() {
	local home_var="$1"
	if [ -d "$SELF_DIR/.git" ]; then
		echo "$SELF_DIR"
		return 0
	fi
	if [ -n "${!home_var:-}" ] && [ -d "${!home_var}/.git" ]; then
		echo "${!home_var}"
		return 0
	fi
	if [ -d "$HOME/github/xxclaude/.git" ]; then
		echo "$HOME/github/xxclaude"
		return 0
	fi
	echo ""
}

# ---- do_update: git pull latest from the repo ---------------------------
# Usage: do_update "dsclaude" "DSCLAUDE_HOME"
do_update() {
	local name="$1" home_var="$2"
	local repo
	repo="$(find_repo "$home_var")"
	if [ -z "$repo" ]; then
		echo "$name: cannot find the xxclaude repo for self-update." >&2
		echo "  Set $home_var=/path/to/xxclaude  or  cd into the repo and run ./$name update" >&2
		exit 1
	fi
	echo "$name: pulling latest from $repo ..."
	git -C "$repo" pull && echo "$name: updated." || {
		echo "$name: git pull failed. Check network or resolve conflicts manually." >&2
		exit 1
	}
	exit 0
}

# ---- extract_key_from_file: get an API key value from a shell rc file ---
# Skips commented-out lines (starting with # after optional whitespace).
# Usage: key="$(extract_key_from_file "$HOME/.zshrc" "DEEPSEEK_API_KEY")"
extract_key_from_file() {
	local file="$1" var="$2"
	[ -f "$file" ] || return 1
	grep -v '^[[:space:]]*#' "$file" |
		grep -E "^[[:space:]]*(export[[:space:]]+)?${var}=" |
		tail -n1 |
		sed -E "s/^[[:space:]]*(export[[:space:]]+)?${var}=//" |
		sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'
}

# ---- resolve_api_key: env var first, then shell rc files ----------------
# Usage: API_KEY="$(resolve_api_key "DEEPSEEK_API_KEY")"
resolve_api_key() {
	local var="$1"
	# 1) Already in environment
	if [ -n "${!var:-}" ]; then
		printf '%s' "${!var}"
		return 0
	fi
	# 2) Shell rc files
	local f candidate
	for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
		candidate="$(extract_key_from_file "$f" "$var" || true)"
		if [ -n "${candidate:-}" ]; then
			printf '%s' "$candidate"
			return 0
		fi
	done
	# Return 0 even when not found: callers use API_KEY="$(resolve_api_key ...)"
	# under `set -e`, and a nonzero status would kill the launcher silently
	# before its friendly "key not found" message can print.
	return 0
}

# ---- export_anthropic_base: set the common ANTHROPIC_* env vars ---------
# Caller must set BASE_URL, API_KEY, MAIN_MODEL, FLASH_MODEL first.
export_anthropic_base() {
	# Clear lingering official Anthropic credentials before launching,
	# otherwise they shadow ANTHROPIC_AUTH_TOKEN and traffic hits api.anthropic.com.
	unset ANTHROPIC_API_KEY 2>/dev/null || true

	export ANTHROPIC_BASE_URL="$BASE_URL"
	export ANTHROPIC_AUTH_TOKEN="$API_KEY"
	export ANTHROPIC_MODEL="$MAIN_MODEL"
	export ANTHROPIC_DEFAULT_OPUS_MODEL="$MAIN_MODEL"
	export ANTHROPIC_DEFAULT_SONNET_MODEL="$MAIN_MODEL"
	export ANTHROPIC_DEFAULT_HAIKU_MODEL="$FLASH_MODEL"

	# Prevent Claude Code from pinging api.anthropic.com for non-essential
	# features (billing check, feature flags) — those always fail on third-
	# party backends and produce noisy connection-error logs.
	export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
}

# ---- check_version: handle --version / -V flag -------------------------
# Usage: check_version "dsclaude" "$@"
# If the first arg is --version or -V, prints version info and exits.
check_version() {
	local name="$1"
	shift
	if [ $# -gt 0 ] && { [ "$1" = "--version" ] || [ "$1" = "-V" ]; }; then
		local repo ver="unknown"
		repo="$(find_repo "DUMMY" 2>/dev/null || true)"
		[ -n "$repo" ] && ver="$(git -C "$repo" describe --tags --always --dirty 2>/dev/null || echo "unknown")"
		echo "$name $ver"
		exit 0
	fi
}

# ---- set_custom_model: expose alternate model in /model picker ----------
# Usage: set_custom_model "$OTHER_MODEL" "$MAIN_MODEL" "$OTHER_DESC"
set_custom_model() {
	local other="$1" main="$2" desc="$3"
	if [ "$other" != "$main" ]; then
		export ANTHROPIC_CUSTOM_MODEL_OPTION="$other"
		export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="$other"
		export ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION="$desc"
	fi
}

# ---- apply_context_and_effort: set CTX/output/effort env vars -----------
# Caller must set CTX, OUTPUT_CAP, EFFORT, LONG_CTX before calling.
apply_context_and_effort() {
	if [ -n "${EFFORT:-}" ]; then export CLAUDE_CODE_EFFORT_LEVEL="$EFFORT"; fi

	local ctx="${CTX:-}"
	if [ -z "$ctx" ] && [ "${LONG_CTX:-0}" = "1" ]; then ctx="1048576"; fi
	if [ -n "$ctx" ]; then
		export CLAUDE_CODE_MAX_CONTEXT_TOKENS="$ctx"
		export DISABLE_COMPACT=1
	fi

	if [ -n "${OUTPUT_CAP:-}" ]; then export CLAUDE_CODE_MAX_OUTPUT_TOKENS="$OUTPUT_CAP"; fi
}

# ---- show_banner_and_launch: print banner and exec claude ----------------
# Usage: show_banner_and_launch "DeepSeek" "$@"
show_banner_and_launch() {
	local label="$1"
	shift
	local banner="🚀 Claude Code on $label  →  $MAIN_MODEL  ($BASE_URL)"
	[ -n "${CTX:-}" ] && banner="$banner  |  ctx=$CTX"
	[ -n "${EFFORT:-}" ] && banner="$banner  |  effort=$EFFORT"
	[ "${OTHER_MODEL:-}" != "$MAIN_MODEL" ] && banner="$banner  (switch mid-session via /model)"
	echo "$banner"
	exec claude "$@"
}
