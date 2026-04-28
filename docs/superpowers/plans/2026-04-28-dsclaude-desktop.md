# dsclaude-desktop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a single bash script `xxclaude/dsclaude-desktop` that drives Claude Desktop's "Configure third-party inference" UI to switch its backend to DeepSeek, with `--revert` to restore Anthropic direct.

**Architecture:** Single self-contained bash file. Bash handles arg parsing, pre-flight checks, and API key resolution; `osascript` heredocs handle macOS UI automation. No external dependencies.

**Tech Stack:** bash, osascript (AppleScript), macOS System Events.

**Spec:** `docs/superpowers/specs/2026-04-28-dsclaude-desktop-design.md`

**Testing strategy:** Per spec, no automated tests for the UI automation portion (UI tests are flaky and the surface is small). Each task includes a **manual verification step** the engineer must run before committing. The probe task (Task 2) generates ground-truth UI labels to bake into later tasks.

---

## File Structure

| File | Purpose |
|---|---|
| `dsclaude-desktop` | Single bash executable. All logic lives here. |

No supporting files. The existing `dsclaude` is **not** modified.

---

## Task 1: Scaffold script with arg parsing and help

**Files:**
- Create: `dsclaude-desktop`

- [ ] **Step 1: Create the file with shebang, header, and arg dispatch**

```bash
#!/usr/bin/env bash
# dsclaude-desktop — switch Claude Desktop's backend between Anthropic and DeepSeek.
#
# Drives the "Developer → Configure third-party inference" UI via AppleScript.
# Companion to ./dsclaude (which targets Claude Code, not the desktop app).
#
# Usage:
#   dsclaude-desktop            # configure: switch Claude Desktop to DeepSeek
#   dsclaude-desktop --revert   # revert:   clear gateway, back to Anthropic direct
#   dsclaude-desktop -h         # help

set -euo pipefail

MODE="configure"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --revert)
      MODE="revert"
      shift
      ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "dsclaude-desktop: unknown argument: $1" >&2
      echo "Run 'dsclaude-desktop -h' for usage." >&2
      exit 2
      ;;
  esac
done

echo "MODE=$MODE"  # placeholder — will be replaced in later tasks
```

- [ ] **Step 2: Make executable**

```bash
chmod +x dsclaude-desktop
```

- [ ] **Step 3: Manually verify arg parsing**

```bash
./dsclaude-desktop -h          # expect: usage block printed
./dsclaude-desktop             # expect: MODE=configure
./dsclaude-desktop --revert    # expect: MODE=revert
./dsclaude-desktop --bogus     # expect: error + exit 2
echo $?                        # confirm 2 on the last one
```

All four outputs must match. If the `-h` block is empty or wrong, the `sed` slice line range is off — adjust the `2,10p` to cover the actual usage comment lines.

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop
git commit -m "Scaffold dsclaude-desktop with arg parsing"
```

---

## Task 2: Probe live Claude Desktop menu structure

This task is a **discovery task**, not code. Its output is a small `MENU_PROBE.md` note (kept locally, not committed) that pins down the exact AppleScript labels later tasks depend on.

The spec acknowledges that we don't yet know exact menu item names (e.g. "Configure third-party inference" vs "Configure Third-Party Inference", and what the non-gateway radio option is called in revert flow).

**Files:**
- Create (local, not committed): `MENU_PROBE.md`

- [ ] **Step 1: Open Claude Desktop, manually navigate the menus once**

Open Claude Desktop. Click `Help → Troubleshooting`. Note the exact label of the "Enable Developer Mode" item. Click it. Confirm a new `Developer` menu appears in the menu bar. Click `Developer → Configure third-party inference`. Note:
- Exact menu bar label of the developer menu (`Developer`?)
- Exact menu item label (`Configure third-party inference`? `Configure Third-Party Inference`?)
- The dialog's title bar text
- The Connection Type dropdown's options — write down the **exact strings** for both "Gateway (Anthropic-compatible)" and the non-gateway default option (likely "Anthropic Direct" or "Default")
- The button text on the Apply control (e.g. `Apply locally → Relaunch` vs `Apply` vs `Apply & Relaunch`)

Cancel out of the dialog without saving.

- [ ] **Step 2: Dump menu hierarchy via osascript for confirmation**

```bash
osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Claude"
    set helpItems to name of every menu item of menu "Help" of menu bar 1
    set devExists to (exists menu bar item "Developer" of menu bar 1)
    if devExists then
      set devItems to name of every menu item of menu "Developer" of menu bar 1
    else
      set devItems to {}
    end if
    return {helpItems, devExists, devItems}
  end tell
end tell
APPLESCRIPT
```

Expected: a list-of-lists with Help menu items, then `true|false` for whether Developer menu exists, then Developer menu items if it does. Capture the output.

- [ ] **Step 3: Write findings into a local note file**

```bash
cat > MENU_PROBE.md <<'EOF'
# Live UI labels (probed on YYYY-MM-DD, Claude Desktop vX.Y.Z)
HELP_TROUBLESHOOTING_SUBMENU = "Troubleshooting"
ENABLE_DEV_MODE_LABEL        = "Enable Developer Mode"
DISABLE_DEV_MODE_LABEL       = "Disable Developer Mode"
DEVELOPER_MENU_LABEL         = "Developer"
CONFIGURE_INFERENCE_LABEL    = "Configure third-party inference"   # ← fill in actual
GATEWAY_OPTION_LABEL         = "Gateway (Anthropic-compatible)"     # ← fill in actual
ANTHROPIC_DIRECT_LABEL       = "Anthropic Direct"                   # ← fill in actual
APPLY_BUTTON_LABEL           = "Apply locally → Relaunch"           # ← fill in actual
EOF
```

Edit each `← fill in actual` to match what you observed. **Add `MENU_PROBE.md` to `.gitignore` or just don't commit it.**

- [ ] **Step 4: No commit — this is local discovery**

Skip committing. The values from this file get hardcoded into the script in later tasks.

---

## Task 3: Pre-flight checks

**Files:**
- Modify: `dsclaude-desktop`

- [ ] **Step 1: Add pre-flight function above the arg-parsing block**

Replace the placeholder `echo "MODE=$MODE"` and what follows with this. Put the function near the top, between the header and the arg loop:

```bash
preflight() {
  if [[ "$(uname)" != "Darwin" ]]; then
    echo "dsclaude-desktop: macOS only (Claude Desktop on this script's target)." >&2
    exit 1
  fi

  if [[ ! -d "/Applications/Claude.app" ]]; then
    echo "dsclaude-desktop: Claude.app not found in /Applications." >&2
    echo "Install from https://claude.ai/download and re-run." >&2
    exit 1
  fi

  if ! command -v osascript >/dev/null 2>&1; then
    echo "dsclaude-desktop: osascript not found (this should never happen on macOS)." >&2
    exit 1
  fi

  # Accessibility probe: try to read the frontmost process name.
  # If accessibility is denied, this fails with -1719 or similar.
  if ! osascript -e 'tell application "System Events" to get name of first process' >/dev/null 2>&1; then
    cat >&2 <<'EOF'
dsclaude-desktop: Accessibility permission not granted to your terminal.
  Open: System Settings → Privacy & Security → Accessibility
  Enable: Terminal (or iTerm, Warp, etc. — whichever runs this script)
  Re-run this script after granting.
EOF
    exit 1
  fi
}
```

Then after arg parsing, call `preflight`. The end of the script now looks like:

```bash
# (arg parsing block above)

preflight
echo "MODE=$MODE"  # placeholder for next tasks
```

- [ ] **Step 2: Manually verify pre-flight passes on this machine**

```bash
./dsclaude-desktop
# expect: MODE=configure  (after pre-flight passes silently)
```

- [ ] **Step 3: Manually verify pre-flight catches missing Claude.app**

Temporarily rename the app:

```bash
sudo mv /Applications/Claude.app /Applications/Claude.app.bak
./dsclaude-desktop
# expect: error message about Claude.app not found, exit 1
sudo mv /Applications/Claude.app.bak /Applications/Claude.app
```

(Skip this step if you'd rather not move the app; the path check is trivially correct via inspection.)

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop
git commit -m "Add pre-flight checks (macOS, Claude.app, osascript, Accessibility)"
```

---

## Task 4: API key resolution chain

**Files:**
- Modify: `dsclaude-desktop`

- [ ] **Step 1: Add `resolve_api_key` function below `preflight`**

```bash
# Resolves DEEPSEEK_API_KEY from (in order): env, ~/.zshrc & friends, interactive dialog.
# Prints the key on stdout. Never writes it to disk.
resolve_api_key() {
  if [[ -n "${DEEPSEEK_API_KEY:-}" ]]; then
    printf '%s' "$DEEPSEEK_API_KEY"
    return 0
  fi

  local rc found=""
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile"; do
    [[ -r "$rc" ]] || continue
    found="$(grep -E '^[[:space:]]*export[[:space:]]+DEEPSEEK_API_KEY=' "$rc" 2>/dev/null | tail -1 | sed -E 's/^[^=]*=//; s/^"(.*)"$/\1/; s/^'\''(.*)'\''$/\1/' || true)"
    if [[ -n "$found" ]]; then
      printf '%s' "$found"
      return 0
    fi
  done

  # Interactive fallback via osascript dialog.
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

- [ ] **Step 2: Wire it into the configure path**

Replace the placeholder `echo "MODE=$MODE"` with:

```bash
case "$MODE" in
  configure)
    DEEPSEEK_KEY="$(resolve_api_key)"
    echo "Got key (length: ${#DEEPSEEK_KEY})"  # placeholder for next tasks
    ;;
  revert)
    echo "Revert mode (no key needed)"  # placeholder for next tasks
    ;;
esac
```

- [ ] **Step 3: Manually verify all three resolution paths**

```bash
# Path 1: env var
DEEPSEEK_API_KEY="test-from-env" ./dsclaude-desktop
# expect: "Got key (length: 13)"

# Path 2: shell rc fallback (only if you have it in ~/.zshrc)
unset DEEPSEEK_API_KEY
./dsclaude-desktop
# expect: "Got key (length: <whatever your real key length is>)"

# Path 3: interactive dialog
# Temporarily comment out the export line in your rc, then:
unset DEEPSEEK_API_KEY
./dsclaude-desktop
# expect: a macOS password dialog pops up. Type "test", click OK.
# expect: "Got key (length: 4)"
# Then restore your rc.
```

All three must work. If path 2 finds nothing on a system that has the export, the regex is wrong — debug with `grep -E '^[[:space:]]*export[[:space:]]+DEEPSEEK_API_KEY=' ~/.zshrc`.

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop
git commit -m "Add DEEPSEEK_API_KEY resolution chain (env → rc → dialog)"
```

---

## Task 5: Launch helper + confirmation gate

**Files:**
- Modify: `dsclaude-desktop`

- [ ] **Step 1: Add helpers below `resolve_api_key`**

```bash
ensure_claude_running() {
  if ! pgrep -x "Claude" >/dev/null 2>&1; then
    open -a "Claude"
    # Wait up to 10 seconds for the process to register.
    local i
    for i in 1 2 3 4 5 6 7 8 9 10; do
      pgrep -x "Claude" >/dev/null 2>&1 && return 0
      sleep 1
    done
    echo "dsclaude-desktop: Claude failed to start within 10s." >&2
    exit 1
  fi
}

confirm_or_abort() {
  local action_summary="$1"
  echo
  echo "About to: $action_summary"
  echo "Press Enter to continue, Ctrl-C to abort."
  read -r _
}
```

- [ ] **Step 2: Wire confirmation into both modes**

Update the `case "$MODE"` block to call them:

```bash
case "$MODE" in
  configure)
    DEEPSEEK_KEY="$(resolve_api_key)"
    confirm_or_abort "configure Claude Desktop to use DeepSeek (api.deepseek.com/anthropic) and trigger a relaunch."
    ensure_claude_running
    echo "[stub] would now drive UI to configure DeepSeek"
    ;;
  revert)
    confirm_or_abort "revert Claude Desktop to Anthropic direct (clears gateway config) and trigger a relaunch."
    ensure_claude_running
    echo "[stub] would now drive UI to revert to Anthropic direct"
    ;;
esac
```

- [ ] **Step 3: Manually verify**

```bash
./dsclaude-desktop
# expect: confirmation prompt appears; press Enter; Claude launches if not running;
#         "[stub] would now drive UI..." prints.

./dsclaude-desktop --revert
# expect: same flow, different summary message.
```

Try Ctrl-C at the prompt — script should exit cleanly with no traceback (because of `set -e` it will).

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop
git commit -m "Add launch helper and confirmation gate"
```

---

## Task 6: Forward UI automation — enable Dev Mode + open inference dialog

**Files:**
- Modify: `dsclaude-desktop`

> **Use the labels you wrote in `MENU_PROBE.md` from Task 2.** Replace the placeholder strings below with your probed values if they differ.

- [ ] **Step 1: Add `enable_dev_mode_if_needed` and `open_inference_dialog` helpers**

Place below `confirm_or_abort`:

```bash
enable_dev_mode_if_needed() {
  osascript <<'APPLESCRIPT'
tell application "Claude" to activate
delay 0.5
tell application "System Events"
  tell process "Claude"
    -- If Developer menu already exists, skip.
    if exists menu bar item "Developer" of menu bar 1 then
      return "already_enabled"
    end if
    click menu bar item "Help" of menu bar 1
    delay 0.3
    click menu item "Troubleshooting" of menu "Help" of menu bar item "Help" of menu bar 1
    delay 0.3
    click menu item "Enable Developer Mode" of menu "Troubleshooting" of menu item "Troubleshooting" of menu "Help" of menu bar item "Help" of menu bar 1
    delay 1.0
    return "enabled"
  end tell
end tell
APPLESCRIPT
}

open_inference_dialog() {
  osascript <<'APPLESCRIPT'
tell application "Claude" to activate
delay 0.3
tell application "System Events"
  tell process "Claude"
    click menu bar item "Developer" of menu bar 1
    delay 0.3
    click menu item "Configure third-party inference" of menu "Developer" of menu bar item "Developer" of menu bar 1
    delay 1.0
    return "opened"
  end tell
end tell
APPLESCRIPT
}
```

- [ ] **Step 2: Wire them in (dialog still won't be filled — next task)**

Update the `configure` branch:

```bash
  configure)
    DEEPSEEK_KEY="$(resolve_api_key)"
    confirm_or_abort "configure Claude Desktop to use DeepSeek (api.deepseek.com/anthropic) and trigger a relaunch."
    ensure_claude_running
    enable_dev_mode_if_needed
    open_inference_dialog
    echo "[stub] dialog is open; next task fills + applies"
    ;;
```

- [ ] **Step 3: Manually verify**

Make sure Developer Mode is currently **off** (toggle it off in Help → Troubleshooting if needed). Then:

```bash
./dsclaude-desktop
# Press Enter at the confirmation prompt.
# expect: Claude activates → Help menu briefly opens → Developer mode enables →
#         Developer menu opens → Configure third-party inference dialog appears.
# Manually close the dialog (Cmd-W or click cancel).
```

Then re-run **without** disabling dev mode first:

```bash
./dsclaude-desktop
# expect: skip the enable step (dev menu already exists), open dialog directly.
```

If a step times out or fails: open `MENU_PROBE.md` and confirm the menu/item names match the AppleScript strings exactly. Update the AppleScript strings if needed.

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop
git commit -m "Drive Developer mode + open inference dialog via osascript"
```

---

## Task 7: Forward UI automation — fill fields and apply

**Files:**
- Modify: `dsclaude-desktop`

> The exact UI element types in the inference dialog (popup button vs radio, text field vs secure text field) need to be confirmed via UI inspection. The AppleScript below assumes the most common layout. **If a step fails, use Accessibility Inspector** (built into Xcode) **or `System Events` UI hierarchy queries to confirm**.

- [ ] **Step 1: Add `fill_and_apply_gateway` helper**

```bash
fill_and_apply_gateway() {
  local base_url="$1"
  local api_key="$2"

  # Pass values to AppleScript via env vars (safer than string interpolation).
  BASE_URL="$base_url" API_KEY="$api_key" osascript <<'APPLESCRIPT'
set baseUrl to system attribute "BASE_URL"
set apiKey to system attribute "API_KEY"

tell application "System Events"
  tell process "Claude"
    set frontWin to window 1
    -- Click the Connection Type popup, choose "Gateway (Anthropic-compatible)".
    -- The dialog typically has one popup button; if multiple, this picks the first.
    try
      click pop up button 1 of frontWin
      delay 0.3
      click menu item "Gateway (Anthropic-compatible)" of menu 1 of pop up button 1 of frontWin
      delay 0.3
    end try

    -- Tab into Base URL field and type. Tab again into API Key field and type.
    -- This relies on tab order. If dialog layout changes, switch to clicking text fields by index.
    keystroke tab
    delay 0.1
    keystroke baseUrl
    delay 0.1
    keystroke tab
    delay 0.1
    keystroke apiKey
    delay 0.2

    -- Click the Apply button. Try common labels.
    set applied to false
    repeat with btnLabel in {"Apply locally → Relaunch", "Apply & Relaunch", "Apply"}
      try
        click button (btnLabel as text) of frontWin
        set applied to true
        exit repeat
      end try
    end repeat
    if not applied then
      error "Could not find Apply button — labels probed: Apply locally → Relaunch / Apply & Relaunch / Apply"
    end if
  end tell
end tell
APPLESCRIPT
}
```

- [ ] **Step 2: Wire it into the configure branch**

```bash
  configure)
    DEEPSEEK_KEY="$(resolve_api_key)"
    confirm_or_abort "configure Claude Desktop to use DeepSeek (api.deepseek.com/anthropic) and trigger a relaunch."
    ensure_claude_running
    enable_dev_mode_if_needed
    open_inference_dialog
    fill_and_apply_gateway "https://api.deepseek.com/anthropic" "$DEEPSEEK_KEY"
    cat <<'EOF'

Done. Claude Desktop should be restarting.

When it comes back up:
  1. Click "Continue with Gateway"
  2. Choose model: deepseek-v4-pro  (or deepseek-v4-flash for cheaper/faster)

To revert later:  ./dsclaude-desktop --revert
EOF
    ;;
```

- [ ] **Step 3: Manually verify end-to-end forward path**

Reset state first: in Claude Desktop, Developer → Configure third-party inference → switch back to Anthropic direct → Apply → Relaunch. Confirm you're on plain Anthropic.

Then:

```bash
./dsclaude-desktop
# Press Enter.
# expect:
#   - Claude activates, dialog opens
#   - Connection Type changes to Gateway
#   - Base URL field gets typed in
#   - API Key field gets typed in (hidden)
#   - Apply button gets clicked, app relaunches
# After relaunch:
#   - "Continue with Gateway" prompt appears
#   - Pick deepseek-v4-pro
#   - Send a chat message (e.g. "你好") — should get a Chinese response from DeepSeek
```

If field-typing lands in the wrong field: the tab order assumption is wrong. Replace the `keystroke tab; keystroke baseUrl` pattern with explicit clicks on text fields by index (`click text field 1 of frontWin; keystroke baseUrl` etc.) — confirm indices via Accessibility Inspector.

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop
git commit -m "Fill gateway fields and apply (forward direction complete)"
```

---

## Task 8: Revert UI automation

**Files:**
- Modify: `dsclaude-desktop`

- [ ] **Step 1: Add `revert_to_anthropic_direct` helper**

```bash
revert_to_anthropic_direct() {
  osascript <<'APPLESCRIPT'
tell application "System Events"
  tell process "Claude"
    set frontWin to window 1

    -- Read current Connection Type value to detect no-op.
    set currentValue to ""
    try
      set currentValue to value of pop up button 1 of frontWin
    end try
    if currentValue contains "Anthropic" and not (currentValue contains "Gateway") then
      return "already_direct"
    end if

    -- Switch popup back to "Anthropic Direct" (or whichever non-gateway label was probed).
    try
      click pop up button 1 of frontWin
      delay 0.3
      click menu item "Anthropic Direct" of menu 1 of pop up button 1 of frontWin
      delay 0.3
    on error
      -- Fallback labels in case of UI variation.
      try
        click menu item "Default" of menu 1 of pop up button 1 of frontWin
      end try
    end try

    -- Click Apply (same fallback chain as forward).
    set applied to false
    repeat with btnLabel in {"Apply locally → Relaunch", "Apply & Relaunch", "Apply"}
      try
        click button (btnLabel as text) of frontWin
        set applied to true
        exit repeat
      end try
    end repeat
    if not applied then
      error "Could not find Apply button on revert"
    end if
    return "reverted"
  end tell
end tell
APPLESCRIPT
}
```

- [ ] **Step 2: Wire into the revert branch**

```bash
  revert)
    confirm_or_abort "revert Claude Desktop to Anthropic direct (clears gateway config) and trigger a relaunch."
    ensure_claude_running
    open_inference_dialog
    result="$(revert_to_anthropic_direct)"
    if [[ "$result" == "already_direct" ]]; then
      echo "Already on Anthropic direct — nothing to do. Closing dialog."
      osascript -e 'tell application "System Events" to keystroke "w" using command down' || true
      exit 0
    fi
    cat <<'EOF'

Reverted to Anthropic direct. Claude Desktop is restarting.
Developer Mode left enabled (toggle from Help → Troubleshooting if you want it off).
EOF
    ;;
```

- [ ] **Step 3: Manually verify revert from a configured state**

Confirm Claude Desktop is currently on DeepSeek (from Task 7 verification). Then:

```bash
./dsclaude-desktop --revert
# Press Enter.
# expect:
#   - dialog opens
#   - popup switches to Anthropic Direct
#   - Apply clicked, app relaunches
#   - back to plain Claude with no "Continue with Gateway" prompt
```

- [ ] **Step 4: Manually verify revert no-op**

Without changing anything, run revert again:

```bash
./dsclaude-desktop --revert
# Press Enter.
# expect:
#   - dialog opens
#   - script prints "Already on Anthropic direct — nothing to do. Closing dialog."
#   - dialog closes via Cmd-W
#   - script exits 0
```

- [ ] **Step 5: Commit**

```bash
git add dsclaude-desktop
git commit -m "Add --revert flow with idempotent no-op detection"
```

---

## Task 9: Final hardening + docs touch-up

**Files:**
- Modify: `dsclaude-desktop`
- Modify: `README.md` (or `README_CN.md` if that's the canonical one)

- [ ] **Step 1: Verify the help text matches reality**

```bash
./dsclaude-desktop -h
```

Output should describe both `configure` (default) and `--revert` modes. If it's missing or stale, update the comment block at the top of the file (the one `sed -n '2,9p'` slices) so it's accurate.

- [ ] **Step 2: Add a one-paragraph README mention**

Open `README.md` (and/or `README_CN.md`). Find where `dsclaude` is described. Add a sibling paragraph:

```markdown
### dsclaude-desktop

Switches Claude Desktop's backend between Anthropic and DeepSeek by driving the
"Configure third-party inference" UI. macOS only; requires Accessibility
permission on the terminal that runs it.

    ./dsclaude-desktop            # configure to DeepSeek
    ./dsclaude-desktop --revert   # back to Anthropic direct
```

- [ ] **Step 3: Run a final round-trip**

Forward, send a message, revert, send a message. Both directions must work.

```bash
./dsclaude-desktop          # → DeepSeek
# (chat test)
./dsclaude-desktop --revert # → Anthropic
# (chat test)
```

- [ ] **Step 4: Commit**

```bash
git add dsclaude-desktop README.md README_CN.md
git commit -m "Polish dsclaude-desktop: help text + README mention"
```

---

## Spec coverage check

| Spec section | Covered by |
|---|---|
| File location `xxclaude/dsclaude-desktop` | Task 1 |
| CLI: configure / `--revert` / `-h` | Task 1 |
| Pre-flight: macOS, Claude.app, osascript, Accessibility | Task 3 |
| API key resolution: env → rc → dialog | Task 4 |
| Confirmation gate before mutating | Task 5 |
| Launch app if not running | Task 5 |
| Enable Developer Mode (skip if already on) | Task 6 |
| Open inference dialog | Task 6 |
| Fill Connection Type / Base URL / API Key | Task 7 |
| Click Apply → relaunch | Task 7 |
| Post-relaunch instructions printed | Task 7 |
| Revert: switch back to Anthropic Direct | Task 8 |
| Revert: idempotent no-op | Task 8 |
| Revert leaves Developer Mode on | Task 8 (Step 1 — never touches dev mode toggle) |
| Error handling per step (try/fallback) | Tasks 6, 7, 8 (try blocks + fallback button labels) |
| README touch-up | Task 9 |
| Manual acceptance tests from spec | Task 7 step 3, Task 8 steps 3 & 4, Task 9 step 3 |

No gaps.
