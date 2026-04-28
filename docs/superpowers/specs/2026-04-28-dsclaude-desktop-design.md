# dsclaude-desktop — Claude Desktop ↔ DeepSeek Configurator

**Date**: 2026-04-28
**Status**: Approved (ready for implementation plan)

## Goal

A single bash script that automates Claude Desktop's "Configure third-party inference"
flow to point the app at DeepSeek's Anthropic-compatible API, and that can also
revert that configuration on demand. Companion to the existing `dsclaude` script
(which targets Claude Code, not the desktop app).

## Scope

**In scope**
- macOS only (Claude Desktop on this machine)
- Forward direction: configure Claude Desktop to use DeepSeek as backend
- Reverse direction: clear gateway config, return to Anthropic direct
- Phase 1 UI automation only (configure → trigger relaunch → exit)

**Out of scope (YAGNI)**
- Windows / Linux support
- Toggling between multiple gateways (DeepSeek / Qwen / aihubmix / etc.)
- Post-relaunch automation (the "Continue with Gateway" prompt + model selection)
- Disabling Developer Mode on revert (kept on for convenience)
- Automated UI tests

## User-facing CLI

```
dsclaude-desktop            # configure: switch Claude Desktop to DeepSeek
dsclaude-desktop --revert   # revert: clear gateway, back to Anthropic direct
dsclaude-desktop -h         # help
```

## Architecture

Single bash file at `xxclaude/dsclaude-desktop` (sibling of the existing
`dsclaude`). Bash handles:
- argument parsing
- pre-flight checks
- API key resolution
- terminal-side messaging

`osascript` heredocs handle UI automation. No new files, no dependencies beyond
what macOS ships.

## Flow — forward direction

```
1. Pre-flight checks
     - macOS (Darwin)
     - /Applications/Claude.app exists
     - osascript available
     - Accessibility permission granted (probe via System Events;
       on failure, print path to System Settings → Privacy → Accessibility)

2. Resolve DEEPSEEK_API_KEY
     a. $DEEPSEEK_API_KEY env var
     b. grep ~/.zshrc, ~/.bashrc, ~/.bash_profile, ~/.profile
        for `export DEEPSEEK_API_KEY=...`
     c. osascript display dialog → prompt user to paste key
        (default answer hidden, password style)
     - Key is held in shell variable; never written to disk by this script

3. Confirmation gate
     - Print summary of intended actions, wait for Enter
     - User can Ctrl-C out

4. Launch Claude Desktop if not running, wait for window

5. UI automation (osascript)
     a. If menu shows "Enable Developer Mode": click it
        Else (already shows "Disable Developer Mode"): skip
     b. Developer → Configure third-party inference
     c. Connection Type → "Gateway (Anthropic-compatible)"
     d. Gateway Base URL → https://api.deepseek.com/anthropic
     e. Gateway API Key → $DEEPSEEK_API_KEY (via keystroke)
     f. Click "Apply locally → Relaunch"

6. Print finishing message:
     "Claude Desktop is restarting. When it comes back up, click
      'Continue with Gateway' and pick deepseek-v4-pro."
```

## Flow — `--revert` direction

```
1. Pre-flight checks (same as forward)

2. Skip API key resolution

3. Confirmation gate

4. Launch Claude Desktop if not running, wait for window

5. UI automation
     a. Developer → Configure third-party inference
     b. Switch Connection Type back to "Anthropic Direct"
        (or whatever the non-gateway option is; the implementation
        plan should probe live UI labels and use a small fallback list)
     c. Apply → Relaunch
     d. Developer Mode is left enabled

6. Print finishing message:
     "Reverted to Anthropic direct. Claude Desktop is restarting."
```

## Key technical decisions

| Decision | Rationale |
|---|---|
| Bash + osascript heredocs (not pure AppleScript, not Python) | Matches `dsclaude` style; bash is good at env / rc parsing, AppleScript at UI driving |
| Phase 1 only (no post-relaunch automation) | The script's process dies on app relaunch; re-attaching is fragile. One manual click is acceptable |
| Don't disable Developer Mode on revert | Toggling Developer Mode goes through Help → Troubleshooting; leaving it on saves friction next time |
| Forward overwrites without state-checking | Simpler than detecting current gateway state; idempotent in practice |
| `--revert` no-ops gracefully if already on Anthropic direct | Nice UX; detect by reading the current Connection Type before mutating |
| Use `keystroke` instead of setting field values directly | macOS dialog inputs often reject programmatic value-setting; keystroke is reliable |
| Click menu items via `System Events` menu hierarchy, not keyboard shortcuts | Shortcuts vary by locale; menu paths are stable |

## Error handling

Every UI automation step is wrapped in AppleScript `try` blocks. On failure
the script:
1. Prints which step failed (e.g. "Failed at: open Configure third-party inference dialog")
2. Prints a likely cause + remediation hint, e.g.:
   - "Claude Desktop may be too old — please update from claude.ai/download"
   - "Accessibility not granted — open System Settings → Privacy → Accessibility and enable Terminal"
   - "Developer menu not found — confirm app version supports third-party inference"
3. Exits non-zero

No automatic rollback. The user retains full control via the Developer menu.

## Idempotency

| State on entry | Forward (`dsclaude-desktop`) | Revert (`--revert`) |
|---|---|---|
| Fresh / Anthropic direct | Configure DeepSeek | No-op + message |
| Already DeepSeek | Re-configure (overwrite) | Revert |
| Other gateway | Overwrite to DeepSeek | Revert to Anthropic |

## Testing

No automated tests (UI automation is hard to unit test reliably).

Manual acceptance:
1. Fresh Claude Desktop install → run `dsclaude-desktop` → confirm gateway is set, restart, send a Chinese prompt, confirm DeepSeek-style response
2. Run `dsclaude-desktop --revert` → confirm Anthropic direct restored
3. Run `dsclaude-desktop --revert` twice → second run should print no-op message
4. Revoke Accessibility permission → run script → confirm clear remediation message
5. Unset DEEPSEEK_API_KEY and remove from rc files → run script → confirm interactive password prompt fires

## File layout

```
xxclaude/
├── dsclaude                    # existing — Claude Code → DeepSeek
├── dsclaude-desktop            # NEW — Claude Desktop → DeepSeek
└── docs/superpowers/specs/
    └── 2026-04-28-dsclaude-desktop-design.md   # this file
```

## References

- [DeepSeek Anthropic-compatible API](https://api-docs.deepseek.com/guides/anthropic_api)
- [AIHubMix Claude Desktop setup guide](https://docs.aihubmix.com/en/api/claude-desktop) — same UI flow, different gateway URL
- Existing sibling: `xxclaude/dsclaude` (env var resolution + rc fallback pattern reused here)
