#!/usr/bin/env bash
# codex-setup.sh — generate ~/.codex/config.toml with all your available backends.
#
# Detects which API keys you've set (env or shell rc), then writes a Codex
# config.toml pre-filled with provider blocks for every backend you can use.
# The first detected key becomes the default provider.
#
# Codex only speaks the OpenAI Responses API (Chat Completions support was
# removed in early 2026). Providers are wired accordingly:
#   - Native Responses (direct):  dashscope, ark, longcat, minimax
#   - Chat-only (via local adapter codex-adapter.mjs): deepseek, moonshot,
#     zhipu, tokenhub, siliconflow
# For adapter-backed providers, start the adapter before running codex:
#   nohup node codex-adapter.mjs > ~/.codex/adapter.log 2>&1 &
#
# Usage:
#   ./codex-setup.sh               # interactive: pick from detected keys
#   ./codex-setup.sh --dry-run     # print the config, don't write it
#   ./codex-setup.sh --force deepseek  # set deepseek as default

set -euo pipefail

DRY_RUN=0; FORCE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=1 ;; --force) FORCE="$2"; shift ;;
    *) echo "codex-setup.sh: unknown option: $1" >&2; exit 1 ;;
  esac; shift
done

get_key() {
  local var="$1"
  if [ -n "${!var:-}" ]; then printf '%s' "${!var}"; return 0; fi
  local f candidate
  for f in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [ -f "$f" ] || continue
    candidate="$(grep -v '^[[:space:]]*#' "$f" 2>/dev/null|grep -E "^[[:space:]]*(export[[:space:]]+)?${var}="|tail -1|sed -E "s/^[[:space:]]*(export[[:space:]]+)?${var}=//"|sed -E 's/^"(.*)"$/\1/; s/^'"'"'(.*)'"'"'$/\1/'||true)"
    if [ -n "${candidate:-}" ]; then printf '%s' "$candidate"; return 0; fi
  done; return 1
}

# Adapter port for chat-only providers (codex-adapter.mjs).
ADAPTER_PORT="${CODEX_ADAPTER_PORT:-8317}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Provider data: id label base_url key_var model need_noauth mode
# mode: responses = provider natively supports the OpenAI Responses API
#       adapter   = chat-only; routed through the local codex-adapter.mjs
# Separated by | for easy parsing.
PROVIDERS_DATA=(
  "deepseek|DeepSeek|http://127.0.0.1:${ADAPTER_PORT}/deepseek/v1|DEEPSEEK_API_KEY|deepseek-v4-pro|no|adapter"
  "dashscope|Qwen (Bailian)|https://dashscope.aliyuncs.com/compatible-mode/v1|DASHSCOPE_API_KEY|qwen-plus|no|responses"
  "moonshot|Moonshot Kimi|http://127.0.0.1:${ADAPTER_PORT}/moonshot/v1|KIMI_API_KEY|kimi-k2.5|no|adapter"
  "zhipu|ZhipuAI GLM|http://127.0.0.1:${ADAPTER_PORT}/zhipu/v1|GLM_API_KEY|glm-5.2|yes|adapter"
  "ark|Volcengine Ark|https://ark.cn-beijing.volces.com/api/v3|ARK_API_KEY|doubao-seed-2.0-code|yes|responses"
  "longcat|Meituan LongCat|https://api.longcat.chat/openai/v1|LONGCAT_API_KEY|LongCat-2.0|yes|responses"
  "minimax|MiniMax|https://api.minimaxi.com/v1|MINIMAX_API_KEY|MiniMax-M3|yes|responses"
  "tokenhub|Tencent TokenHub|http://127.0.0.1:${ADAPTER_PORT}/tokenhub/v1|HY_API_KEY|hy3-preview|yes|adapter"
  "siliconflow|SiliconFlow|http://127.0.0.1:${ADAPTER_PORT}/siliconflow/v1|SF_API_KEY|deepseek-ai/DeepSeek-V4-PRO|yes|adapter"
)

# Detect available providers.
available_ids=()
available_labels=()
for entry in "${PROVIDERS_DATA[@]}"; do
  IFS='|' read -r pid plabel purl pkey pmodel pnoauth pmode <<< "$entry"
  k="$(get_key "$pkey" || true)"
  if [ -n "${k:-}" ]; then available_ids+=("$pid"); available_labels+=("$plabel"); fi
done

if [ ${#available_ids[@]} -eq 0 ]; then
  echo "codex-setup.sh: no known API keys found. Set one in your ~/.zshrc:" >&2
  echo "  export DEEPSEEK_API_KEY=sk-..." >&2
  echo "  export KIMI_API_KEY=sk-..." >&2
  exit 1
fi

# Pick default.
DEFAULT_ID="${available_ids[0]}"; DEFAULT_LABEL="${available_labels[0]}"
if [ -n "$FORCE" ]; then
  found=0; for i in "${!available_ids[@]}"; do
    if [ "${available_ids[$i]}" = "$FORCE" ]; then DEFAULT_ID="$FORCE"; DEFAULT_LABEL="${available_labels[$i]}"; found=1; break; fi
  done
  if [ "$found" = "0" ]; then echo "codex-setup.sh: provider '$FORCE' key not set." >&2; exit 1; fi
elif [ ${#available_ids[@]} -gt 1 ] && [ ! -t 0 ]; then
  # Non-interactive with multiple keys — use first.
  :
elif [ ${#available_ids[@]} -gt 1 ]; then
  echo "Multiple API keys detected. Which default provider?"
  for i in "${!available_ids[@]}"; do echo "  $((i+1))) ${available_labels[$i]}"; done
  read -r -p "Choice [1-${#available_ids[@]}] (default 1): " choice
  idx="${choice:-1}"
  if [ "$idx" -ge 1 ] 2>/dev/null && [ "$idx" -le "${#available_ids[@]}" ]; then
    DEFAULT_ID="${available_ids[$((idx-1))]}"; DEFAULT_LABEL="${available_labels[$((idx-1))]}"
  fi
fi

# Find default model.
DEFAULT_MODEL=""; for entry in "${PROVIDERS_DATA[@]}"; do
  IFS='|' read -r pid plabel purl pkey pmodel pnoauth pmode <<< "$entry"
  [ "$pid" = "$DEFAULT_ID" ] && { DEFAULT_MODEL="$pmodel"; break; }
done

# ---- Generate config.toml --------------------------------------------------
CONFIG_PATH="$HOME/.codex/config.toml"

generate_toml() {
  echo "# Generated by codex-setup.sh — $(date +%Y-%m-%d)"
  echo "# Re-run codex-setup.sh to refresh when you add new API keys."
  echo ""
  echo "model = \"$DEFAULT_MODEL\""
  echo "model_provider = \"$DEFAULT_ID\""
  echo ""

  for entry in "${PROVIDERS_DATA[@]}"; do
    IFS='|' read -r pid plabel purl pkey pmodel pnoauth pmode <<< "$entry"
    # Only include if available.
    found=0; for aid in "${available_ids[@]}"; do [ "$aid" = "$pid" ] && found=1; done
    [ "$found" = "0" ] && continue

    echo "# ---- $plabel ----"
    if [ "$pmode" = "adapter" ]; then
      echo "# Chat-only upstream: routed through the local codex-adapter.mjs proxy."
      echo "# Start it first:  nohup node ${SCRIPT_DIR}/codex-adapter.mjs > ~/.codex/adapter.log 2>&1 &"
    fi
    echo "[model_providers.$pid]"
    echo "name = \"$plabel\""
    echo "base_url = \"$purl\""
    echo "env_key = \"$pkey\""
    echo "wire_api = \"responses\""
    if [ "$pnoauth" = "yes" ]; then echo "requires_openai_auth = false"; fi
    echo ""
  done
}

# Modern Codex profiles live in separate files (~/.codex/<name>.config.toml);
# the legacy [profiles.*] tables in config.toml are rejected by current Codex.
write_profile_files() {
  for entry in "${PROVIDERS_DATA[@]}"; do
    IFS='|' read -r pid plabel purl pkey pmodel pnoauth pmode <<< "$entry"
    found=0; for aid in "${available_ids[@]}"; do [ "$aid" = "$pid" ] && found=1; done
    [ "$found" = "0" ] && continue
    printf 'model = "%s"\nmodel_provider = "%s"\n' "$pmodel" "$pid" > "$HOME/.codex/$pid.config.toml"
  done
}

# True if any available provider is adapter-backed.
needs_adapter() {
  for entry in "${PROVIDERS_DATA[@]}"; do
    IFS='|' read -r pid plabel purl pkey pmodel pnoauth pmode <<< "$entry"
    for aid in "${available_ids[@]}"; do
      [ "$aid" = "$pid" ] && [ "$pmode" = "adapter" ] && return 0
    done
  done
  return 1
}

if [ "$DRY_RUN" = "1" ]; then
  generate_toml
  echo "# Dry run — no file written."
else
  mkdir -p "$HOME/.codex"
  if [ -f "$CONFIG_PATH" ]; then
    cp "$CONFIG_PATH" "${CONFIG_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    echo "Backed up existing config."
  fi
  generate_toml > "$CONFIG_PATH"
  write_profile_files
  echo "✓ Wrote $CONFIG_PATH (default: $DEFAULT_LABEL)"
  echo "✓ Wrote profile files: $(for id in "${available_ids[@]}"; do printf '%s.config.toml ' "$id"; done)"
  echo ""
  echo "Quick-switch profiles:"
  for id in "${available_ids[@]}"; do echo "  codex --profile $id"; done
  if needs_adapter; then
    echo ""
    echo "⚠ Some of your providers are chat-only and need the local adapter."
    echo "  Start it once (survives until reboot):"
    echo "    nohup node ${SCRIPT_DIR}/codex-adapter.mjs > ~/.codex/adapter.log 2>&1 &"
    echo "  Check:  curl http://127.0.0.1:${ADAPTER_PORT}/health"
  fi
fi
