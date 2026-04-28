# dsclaude-desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Build `xxclaude/dsclaude-desktop` — a bash script that configures Claude Desktop's inference backend to point at DeepSeek by editing JSON config files and restarting the app. No `--revert`: the user toggles modes via Claude Desktop's launch chooser.

**Architecture:** Single bash file (~60 lines). Edits two JSON files in `~/Library/Application Support/Claude-3p/configLibrary/` via `/usr/bin/jq`, then `killall Claude && open -a Claude`. No UI automation.

**Tech Stack:** bash, /usr/bin/jq, /usr/bin/uuidgen, osascript (only for the API-key fallback dialog).

**Spec:** `docs/superpowers/specs/2026-04-28-dsclaude-desktop-design.md`

**Testing strategy:** No automated tests. Each task ends with a manual verification step that exercises the actual config files and Claude Desktop.

---

## File Structure

| File | Purpose |
|---|---|
| `dsclaude-desktop` | Single bash executable. All logic. |

---

## Task 1: Scaffold + arg parsing + pre-flight + API key resolution

**Files:**
- Create: `dsclaude-desktop`

- [ ] **Step 1: Write the file**

```bash
#!/usr/bin/env bash
# dsclaude-desktop — configure Claude Desktop to use DeepSeek as inference backend.
#
# Edits ~/Library/Application Support/Claude-3p/configLibrary/{_meta,<uuid>}.json
# and restarts Claude Desktop. macOS only.
#
# Usage:
#   dsclaude-desktop      # configure to DeepSeek and restart
#   dsclaude-desktop -h   # help
#
# Note: Once a third-party gateway is active, Claude Desktop's Chat mode is
# unavailable — only Cowork (3P) and Code modes work (Chat depends on
# Anthropic-hosted features). To use Chat: at Claude Desktop's launch chooser
# pick "Continue with Anthropic", or toggle "Skip login-mode chooser" off in
# Developer → Configure Third-Party Inference.

set -euo pipefail

CONFIG_DIR="$HOME/Library/Application Support/Claude-3p/configLibrary"
META="$CONFIG_DIR/_meta.json"
ENTRY_NAME="dsclaude-desktop"
BASE_URL="https://api.deepseek.com/anthropic"
AUTH_SCHEME="bearer"
MAIN_MODEL="deepseek-v4-pro"
FAST_MODEL="deepseek-v4-flash"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "dsclaude-desktop: unknown argument: $1" >&2
      echo "Run 'dsclaude-desktop -h' for usage." >&2
      exit 2
      ;;
  esac
done

preflight() {
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "dsclaude-desktop: macOS only." >&2
    exit 1
  fi
  if [[ ! -d "/Applications/Claude.app" ]]; then
    echo "dsclaude-desktop: /Applications/Claude.app not found. Install from https://claude.ai/download." >&2
    exit 1
  fi
  if [[ ! -x "/usr/bin/jq" ]]; then
    echo "dsclaude-desktop: /usr/bin/jq not found (required on macOS Sonoma+)." >&2
    exit 1
  fi
}

# Resolves DEEPSEEK_API_KEY from (in order): env, ~/.zshrc & friends, osascript prompt.
# Prints the key on stdout.
resolve_api_key() {
  if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
    printf '%s' "$DEEPSEEK_API_KEY"
    return 0
  fi
  local rc found=""
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [[ -r "$rc" ]] || continue
    found="$(grep -E '^[[:space:]]*export[[:space:]]+DEEPSEEK_API_KEY=' "$rc" 2>/dev/null \
      | tail -1 \
      | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/' \
      || true)"
    if [[ -n "$found" ]]; then
      printf '%s' "$found"
      return 0
    fi
  done
  local key
  key="$(osascript <<'APPLESCRIPT' 2>/dev/null || true
try
  set theKey to text returned of (display dialog ¬
    "DeepSeek API Key not found in env or shell rc.\nPaste your DeepSeek API Key:" ¬
    default answer "" ¬
    with hidden answer ¬
    with title "dsclaude-desktop")
  return theKey
on error
  return ""
end try
APPLESCRIPT
)"
  if [[ -z "$key" ]]; then
    echo "dsclaude-desktop: no DeepSeek API Key provided. Aborting." >&2
    exit 1
  fi
  printf '%s' "$key"
}

preflight
DEEPSEEK_KEY="$(resolve_api_key)"
echo "Resolved key (length: ${#DEEPSEEK_KEY})"  # placeholder — Task 2 replaces
```

- [ ] **Step 2: Make executable**

```bash
chmod +x dsclaude-desktop
```

- [ ] **Step 3: Manually verify**

```bash
./dsclaude-desktop -h           # expect: usage block (lines 2–16)
./dsclaude-desktop --bogus      # expect: error + exit 2

DEEPSEEK_API_KEY="abc12345" ./dsclaude-desktop  # expect: "Resolved key (length: 8)"

# Pull from rc:
unset DEEPSEEK_API_KEY; ./dsclaude-desktop
# expect: length matches your real key

# Dialog fallback:
# Temporarily comment out the export in your rc, then:
unset DEEPSEEK_API_KEY; ./dsclaude-desktop
# expect: macOS password dialog → enter test value → length matches what you typed
```

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop
git commit -m "Scaffold dsclaude-desktop with args, pre-flight, key resolution"
```

---

## Task 2: Configure flow — write entry, update meta, restart

**Files:**
- Modify: `dsclaude-desktop`

- [ ] **Step 1: Add helpers below `resolve_api_key`**

```bash
confirm_or_abort() {
  echo
  echo "About to: $1"
  echo "Press Enter to continue, Ctrl-C to abort."
  read -r _
}

# Write the gateway entry JSON for a given UUID via atomic temp+mv.
write_entry() {
  local uuid="$1"
  local entry_path="$CONFIG_DIR/${uuid}.json"
  local tmp="${entry_path}.tmp"
  jq -n \
    --arg baseUrl "$BASE_URL" \
    --arg apiKey  "$DEEPSEEK_KEY" \
    --arg auth    "$AUTH_SCHEME" \
    --arg main    "$MAIN_MODEL" \
    --arg fast    "$FAST_MODEL" \
    '{
       inferenceProvider: "gateway",
       inferenceGatewayBaseUrl: $baseUrl,
       inferenceGatewayApiKey: $apiKey,
       inferenceGatewayAuthScheme: $auth,
       inferenceModels: [
         {name: $main, supports1m: true},
         {name: $fast, supports1m: true}
       ]
     }' > "$tmp"
  mv "$tmp" "$entry_path"
}

# Ensure _meta.json has an entry named $ENTRY_NAME (creating or reusing its uuid)
# and set appliedId to that uuid. Prints the uuid on stdout.
ensure_meta_entry() {
  mkdir -p "$CONFIG_DIR"
  local existing_uuid=""
  if [[ -f "$META" ]]; then
    existing_uuid="$(jq -r --arg name "$ENTRY_NAME" \
      '.entries[]? | select(.name==$name) | .id' "$META" 2>/dev/null \
      | head -1)"
  fi
  local uuid
  if [[ -n "$existing_uuid" ]]; then
    uuid="$existing_uuid"
  else
    uuid="$(uuidgen)"
  fi
  local tmp="${META}.tmp"
  if [[ -f "$META" ]]; then
    jq --arg id "$uuid" --arg name "$ENTRY_NAME" '
      .appliedId = $id
      | .entries = ((.entries // []) | map(select(.name != $name)) + [{id: $id, name: $name}])
    ' "$META" > "$tmp"
  else
    jq -n --arg id "$uuid" --arg name "$ENTRY_NAME" \
      '{appliedId: $id, entries: [{id: $id, name: $name}]}' > "$tmp"
  fi
  mv "$tmp" "$META"
  printf '%s' "$uuid"
}

restart_claude() {
  killall Claude 2>/dev/null || true
  sleep 1
  open -a Claude
}
```

- [ ] **Step 2: Replace the placeholder at end with the real run**

Replace the line `echo "Resolved key (length: ${#DEEPSEEK_KEY})"  # placeholder — Task 2 replaces` with:

```bash
confirm_or_abort "configure Claude Desktop to use DeepSeek ($BASE_URL) and restart it."
UUID="$(ensure_meta_entry)"
write_entry "$UUID"
restart_claude

cat <<'EOF'

Done. Claude Desktop is restarting with DeepSeek as the inference backend.

Heads up: Chat mode is unavailable while a third-party gateway is active.
You'll see Cowork (3P) and Code modes only. To use Chat:

  - At launch chooser, pick "Continue with Anthropic", OR
  - In Developer → Configure Third-Party Inference, toggle off "Skip
    login-mode chooser" (default is off, so the chooser should appear)

Re-run dsclaude-desktop any time to refresh the gateway config.
EOF
```

- [ ] **Step 3: Manually verify on a fresh state**

```bash
# Reset to fresh
rm -rf "$HOME/Library/Application Support/Claude-3p/configLibrary"

./dsclaude-desktop
# Press Enter at the confirmation.
# expect:
#   - configLibrary/ created
#   - _meta.json: appliedId = some uuid, entries = [{id, name: "dsclaude-desktop"}]
#   - <uuid>.json: gateway config + 2 models
#   - Claude Desktop relaunches in Cowork 3P / Gateway mode
```

Inspect:

```bash
ls -la "$HOME/Library/Application Support/Claude-3p/configLibrary"
jq . "$HOME/Library/Application Support/Claude-3p/configLibrary/_meta.json"
# (entry file content — careful, contains API key in plaintext)
```

Send a message in Cowork or Code mode — should hit DeepSeek successfully.

- [ ] **Step 4: Re-run for idempotency**

```bash
./dsclaude-desktop  # Press Enter
# expect: same uuid reused, no second entry, config rewritten cleanly

jq '.entries | length' "$HOME/Library/Application Support/Claude-3p/configLibrary/_meta.json"
# expect: 1
```

- [ ] **Step 5: Verify mode switching via Claude Desktop UI**

In Claude Desktop, look for the launch chooser or use the in-app option to switch to Anthropic mode. Verify Chat becomes available. Re-run `./dsclaude-desktop` to switch back to gateway. Confirm we don't need a `--revert`.

- [ ] **Step 6: Commit**

```bash
git add dsclaude-desktop
git commit -m "Implement configure flow: write entry, update meta, restart Claude"
```

---

## Task 3: README touch-ups

**Files:**
- Modify: `README.md`
- Modify: `README_CN.md`

- [ ] **Step 1: Add a section describing dsclaude-desktop**

Find the section in `README.md` that describes `dsclaude`. Add this sibling section (matching the existing tone and formatting):

```markdown
### dsclaude-desktop

Configures **Claude Desktop**'s inference backend to point at DeepSeek by editing
`~/Library/Application Support/Claude-3p/configLibrary/` and restarting the app.
macOS only.

```bash
./dsclaude-desktop      # configure and restart Claude Desktop
./dsclaude-desktop -h   # help
```

While a third-party gateway is active, Claude Desktop's Chat mode is unavailable
(Anthropic-hosted feature) — only Cowork and Code modes work. To go back to
Anthropic Chat: pick "Continue with Anthropic" at Claude Desktop's launch
chooser. Re-run `dsclaude-desktop` to switch back to DeepSeek.
```

- [ ] **Step 2: Mirror in `README_CN.md`** (in Chinese, matching existing tone)

- [ ] **Step 3: Run final round-trip**

```bash
./dsclaude-desktop -h   # README example matches actual help text
./dsclaude-desktop      # works end-to-end
```

- [ ] **Step 4: Commit**

```bash
git add README.md README_CN.md
git commit -m "Document dsclaude-desktop in READMEs"
```

---

## Spec coverage check

| Spec section | Covered by |
|---|---|
| Single bash file at `xxclaude/dsclaude-desktop` | Task 1 |
| CLI: configure (default) / `-h` | Task 1 |
| Pre-flight: macOS, Claude.app, jq | Task 1 |
| Help text mentions Chat-mode limitation + how to switch back | Task 1 (header comment) |
| API key chain: env → rc → osascript dialog | Task 1 |
| Confirmation gate | Task 2 |
| Write entry JSON via jq, atomic move | Task 2 |
| _meta.json: ensure entry, set appliedId | Task 2 |
| `uuidgen` for new entries, reuse existing | Task 2 |
| Restart Claude (killall + open) | Task 2 |
| Forward post-message documents Chat limitation + how to revert | Task 2 |
| README mentions in both languages | Task 3 |
| Manual acceptance tests from spec | Task 2 verification steps |

No gaps.
