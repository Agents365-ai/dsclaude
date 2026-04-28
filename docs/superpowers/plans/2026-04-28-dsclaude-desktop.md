# dsclaude-desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task.

**Goal:** Build `xxclaude/dsclaude-desktop` — a bash script that switches Claude Desktop's inference backend to DeepSeek (and back) by editing JSON config files and restarting the app.

**Architecture:** Single bash file (~80 lines). Edits two JSON files in `~/Library/Application Support/Claude-3p/configLibrary/` via `/usr/bin/jq`, then `killall Claude && open -a Claude`. No UI automation.

**Tech Stack:** bash, /usr/bin/jq, /usr/bin/uuidgen, osascript (only for the API-key fallback dialog).

**Spec:** `docs/superpowers/specs/2026-04-28-dsclaude-desktop-design.md`

**Testing strategy:** No automated tests. Each task ends with a **manual verification step** that exercises the actual config files and Claude Desktop.

---

## File Structure

| File | Purpose |
|---|---|
| `dsclaude-desktop` | Single bash executable. All logic. |

---

## Task 1: Scaffold + arg parsing + pre-flight + help

**Files:**
- Create: `dsclaude-desktop`

- [ ] **Step 1: Write the file**

```bash
#!/usr/bin/env bash
# dsclaude-desktop — switch Claude Desktop's inference backend to DeepSeek.
#
# Edits ~/Library/Application Support/Claude-3p/configLibrary/{_meta,<uuid>}.json
# and restarts Claude Desktop. macOS only.
#
# Usage:
#   dsclaude-desktop            # configure: switch to DeepSeek
#   dsclaude-desktop --revert   # revert: clear gateway, back to default
#   dsclaude-desktop -h         # help
#
# Note: Claude Desktop's Chat mode is unavailable while a third-party gateway is
# active — only Cowork (3P) and Code modes work. To use Chat, run --revert.

set -euo pipefail

CONFIG_DIR="$HOME/Library/Application Support/Claude-3p/configLibrary"
META="$CONFIG_DIR/_meta.json"
ENTRY_NAME="dsclaude-desktop"
BASE_URL="https://api.deepseek.com/anthropic"
AUTH_SCHEME="bearer"
MAIN_MODEL="deepseek-v4-pro"
FAST_MODEL="deepseek-v4-flash"

MODE="configure"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --revert) MODE="revert"; shift ;;
    -h|--help)
      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'
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

preflight
echo "MODE=$MODE  CONFIG_DIR=$CONFIG_DIR"  # placeholder for next tasks
```

- [ ] **Step 2: Make executable**

```bash
chmod +x dsclaude-desktop
```

- [ ] **Step 3: Manually verify**

```bash
./dsclaude-desktop -h           # expect: usage block
./dsclaude-desktop              # expect: MODE=configure CONFIG_DIR=...
./dsclaude-desktop --revert     # expect: MODE=revert CONFIG_DIR=...
./dsclaude-desktop --bogus      # expect: error + exit 2
```

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop
git commit -m "Scaffold dsclaude-desktop with args, pre-flight, help"
```

---

## Task 2: API key resolution

**Files:**
- Modify: `dsclaude-desktop`

- [ ] **Step 1: Add `resolve_api_key` function below `preflight`**

```bash
# Resolves DEEPSEEK_API_KEY from (in order): env, ~/.zshrc & friends, osascript prompt.
# Prints the key on stdout. Never writes it to disk in this function.
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
```

- [ ] **Step 2: Wire into the configure path (placeholder still)**

Replace the placeholder line at the bottom with:

```bash
case "$MODE" in
  configure)
    DEEPSEEK_KEY="$(resolve_api_key)"
    echo "Resolved key (length: ${#DEEPSEEK_KEY})"  # placeholder — Task 3 replaces
    ;;
  revert)
    echo "Revert mode (no key needed)"  # placeholder — Task 4 replaces
    ;;
esac
```

- [ ] **Step 3: Manually verify all three paths**

```bash
DEEPSEEK_API_KEY="from-env-test" ./dsclaude-desktop      # expect: length 14
unset DEEPSEEK_API_KEY; ./dsclaude-desktop                # expect: pulls from your rc, length matches
# To test dialog path: temporarily comment out the export in your rc, unset, re-run.
# A macOS password dialog should appear.
```

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop
git commit -m "Add DEEPSEEK_API_KEY resolution chain"
```

---

## Task 3: Forward direction — write config + restart

**Files:**
- Modify: `dsclaude-desktop`

- [ ] **Step 1: Add `confirm_or_abort`, `write_entry`, `update_meta`, `restart_claude` helpers**

Place below `resolve_api_key`:

```bash
confirm_or_abort() {
  echo
  echo "About to: $1"
  echo "Press Enter to continue, Ctrl-C to abort."
  read -r _
}

# Write the gateway entry JSON for a given UUID. API key passed via env to avoid
# leaking into ps output.
write_entry() {
  local uuid="$1"
  local entry_path="$CONFIG_DIR/${uuid}.json"
  local tmp="${entry_path}.tmp"

  DEEPSEEK_KEY="$DEEPSEEK_KEY" \
  BASE_URL="$BASE_URL" \
  AUTH_SCHEME="$AUTH_SCHEME" \
  MAIN_MODEL="$MAIN_MODEL" \
  FAST_MODEL="$FAST_MODEL" \
  jq -n \
    --arg baseUrl  "$BASE_URL" \
    --arg apiKey   "$DEEPSEEK_KEY" \
    --arg auth     "$AUTH_SCHEME" \
    --arg main     "$MAIN_MODEL" \
    --arg fast     "$FAST_MODEL" \
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
    jq -n --arg id "$uuid" --arg name "$ENTRY_NAME" '
      {appliedId: $id, entries: [{id: $id, name: $name}]}
    ' > "$tmp"
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

- [ ] **Step 2: Wire into the configure branch**

Replace the configure branch body:

```bash
  configure)
    DEEPSEEK_KEY="$(resolve_api_key)"
    confirm_or_abort "configure Claude Desktop to use DeepSeek ($BASE_URL) and restart it."
    UUID="$(ensure_meta_entry)"
    write_entry "$UUID"
    restart_claude
    cat <<EOF

Done. Claude Desktop is restarting with DeepSeek as the inference backend.

Note: Chat mode is unavailable in third-party gateway mode (Anthropic-hosted feature).
You can use Cowork (3P) and Code modes. To go back to Anthropic Chat:

  ./dsclaude-desktop --revert

EOF
    ;;
```

- [ ] **Step 3: Manually verify forward path on a fresh state**

```bash
# Reset to fresh
rm -rf "$HOME/Library/Application Support/Claude-3p/configLibrary"

./dsclaude-desktop
# Press Enter at the confirmation.
# expect:
#   - configLibrary/ created
#   - _meta.json contains appliedId = some uuid, entries = [{id, name: "dsclaude-desktop"}]
#   - <uuid>.json contains the gateway config + 2 models
#   - Claude Desktop relaunches in Cowork 3P / Gateway mode
```

Inspect the files:

```bash
ls -la "$HOME/Library/Application Support/Claude-3p/configLibrary"
cat "$HOME/Library/Application Support/Claude-3p/configLibrary/_meta.json"
# (entry file content — careful, contains API key)
```

Then send a message in Cowork or Code mode — should hit DeepSeek successfully.

- [ ] **Step 4: Re-run forward (idempotency check)**

```bash
./dsclaude-desktop
# Press Enter.
# expect: same uuid is reused (no second entry created), config rewritten,
#         Claude restarts cleanly.
```

Verify entries still has length 1:

```bash
jq '.entries | length' "$HOME/Library/Application Support/Claude-3p/configLibrary/_meta.json"
# expect: 1
```

- [ ] **Step 5: Commit**

```bash
git add dsclaude-desktop
git commit -m "Implement forward direction: write entry, update meta, restart"
```

---

## Task 4: Revert direction + final polish

**Files:**
- Modify: `dsclaude-desktop`
- Modify: `README.md` and `README_CN.md`

- [ ] **Step 1: Add `revert_meta` helper below `restart_claude`**

```bash
# Sets _meta.json appliedId to null. Returns "noop" if already null/missing,
# "reverted" otherwise.
revert_meta() {
  if [[ ! -f "$META" ]]; then
    echo "noop"
    return 0
  fi
  local current
  current="$(jq -r '.appliedId // "null"' "$META" 2>/dev/null || echo "null")"
  if [[ "$current" == "null" ]]; then
    echo "noop"
    return 0
  fi
  local tmp="${META}.tmp"
  jq '.appliedId = null' "$META" > "$tmp"
  mv "$tmp" "$META"
  echo "reverted"
}
```

- [ ] **Step 2: Wire into the revert branch**

Replace the revert branch body:

```bash
  revert)
    confirm_or_abort "revert Claude Desktop to default (clear gateway) and restart it."
    result="$(revert_meta)"
    if [[ "$result" == "noop" ]]; then
      echo "Already on default — no third-party inference active. Nothing to do."
      exit 0
    fi
    restart_claude
    cat <<'EOF'

Reverted. Claude Desktop is restarting in default mode (Anthropic Chat available).
Your DeepSeek entry is preserved in configLibrary/ — re-run dsclaude-desktop to re-apply.

EOF
    ;;
```

- [ ] **Step 3: Manually verify revert path**

```bash
# Assumes Task 3 left you in DeepSeek mode.
./dsclaude-desktop --revert
# Press Enter.
# expect:
#   - _meta.json appliedId becomes null
#   - entries[] still contains the dsclaude-desktop entry (preserved)
#   - Claude Desktop relaunches in normal Anthropic mode (Chat visible)
```

Inspect:

```bash
jq '.appliedId' "$HOME/Library/Application Support/Claude-3p/configLibrary/_meta.json"
# expect: null

jq '.entries | length' "$HOME/Library/Application Support/Claude-3p/configLibrary/_meta.json"
# expect: 1
```

- [ ] **Step 4: Verify revert no-op**

```bash
./dsclaude-desktop --revert
# expect: "Already on default — ... Nothing to do." and exit 0 immediately (no restart)
```

- [ ] **Step 5: Re-apply after revert**

```bash
./dsclaude-desktop
# Press Enter.
# expect: same uuid, appliedId set back to that uuid, Claude restarts to gateway.
```

- [ ] **Step 6: Update READMEs with one paragraph**

Find the section in `README.md` that describes `dsclaude`. Add a sibling paragraph:

```markdown
### dsclaude-desktop

Switches **Claude Desktop**'s inference backend between Anthropic and DeepSeek by
editing `~/Library/Application Support/Claude-3p/configLibrary/` and restarting
the app. macOS only.

```bash
./dsclaude-desktop          # switch to DeepSeek
./dsclaude-desktop --revert # back to default
```

Note: while a third-party gateway is active, Claude Desktop's Chat mode is
unavailable (Anthropic-hosted feature) — only Cowork and Code modes work.
```

Mirror the addition into `README_CN.md` (in Chinese, matching the existing tone).

- [ ] **Step 7: Commit**

```bash
git add dsclaude-desktop README.md README_CN.md
git commit -m "Add --revert flow and document dsclaude-desktop in READMEs"
```

---

## Spec coverage check

| Spec section | Covered by |
|---|---|
| File location, single bash file | Task 1 |
| CLI: configure / `--revert` / `-h` | Task 1 |
| Pre-flight: macOS, Claude.app, jq | Task 1 |
| Help text mentions Chat-mode limitation | Task 1 (header comment) |
| API key chain: env → rc → osascript dialog | Task 2 |
| Confirmation gate | Task 3 (forward), Task 4 (revert) |
| Write entry JSON via jq, atomic move | Task 3 |
| _meta.json: ensure entry, set appliedId | Task 3 |
| `uuidgen` for new entries, reuse for existing | Task 3 |
| Restart Claude (killall + open) | Task 3 |
| Forward post-message documents Chat limitation | Task 3 |
| Revert: appliedId = null, preserve entries | Task 4 |
| Revert idempotent no-op | Task 4 |
| README mentions | Task 4 |
| Manual acceptance tests from spec | Tasks 3 & 4 verification steps |

No gaps.
