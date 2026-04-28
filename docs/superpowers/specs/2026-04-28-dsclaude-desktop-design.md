# dsclaude-desktop — Claude Desktop ↔ DeepSeek Configurator

**Date**: 2026-04-28
**Status**: Approved (rewritten after live discovery — see "Discovery notes" at end)

## Goal

A single bash script that configures Claude Desktop's third-party inference
backend to point at DeepSeek. Companion to the existing `dsclaude` script (which
targets Claude Code, not the desktop app).

No revert command: Claude Desktop natively supports both modes (Anthropic login
and Gateway) and the user picks at launch via the in-app chooser. The script
just plants the gateway config; the user toggles modes through Claude Desktop's
own UI.

## Scope

**In scope**
- macOS only
- Configure Claude Desktop to use DeepSeek as a gateway (idempotent)
- Restart Claude Desktop so changes take effect

**Out of scope (YAGNI)**
- Revert command (Claude Desktop's launch chooser handles this natively)
- Windows / Linux
- Multiple gateway backends (DeepSeek / Qwen / aihubmix toggle)
- Recovery from a corrupted Claude Desktop config (use `Reset App Data…`)

**Important user-facing limitation (not fixable by this script)**
- Once any third-party gateway is configured AND active, Claude Desktop's
  **Chat** mode is unavailable — only **Cowork (3P)** and **Code** modes work,
  because Chat depends on Anthropic-hosted features (memory, projects,
  artifacts). To use Chat, pick "Continue with Anthropic" in Claude Desktop's
  launch chooser (or toggle "Skip login-mode chooser" off in the dialog).

## User-facing CLI

```
dsclaude-desktop            # configure: plant DeepSeek gateway config and restart
dsclaude-desktop -h         # help
```

## Architecture

Single bash file at `xxclaude/dsclaude-desktop`. Edits two JSON files in
`~/Library/Application Support/Claude-3p/configLibrary/`, then restarts Claude
Desktop. **No osascript / UI driving.**

JSON manipulation via `/usr/bin/jq` (Apple-shipped on Sonoma+).

## Config files (the discovery)

Location: `~/Library/Application Support/Claude-3p/configLibrary/`

### `_meta.json`
```json
{
  "appliedId": "<uuid>",
  "entries": [
    {"id": "<uuid>", "name": "Default"}
  ]
}
```
- `appliedId`: which entry is currently in effect. **`null` (or absent) = no
  third-party inference, vanilla Anthropic mode.**
- `entries`: array of available configs.

### `<uuid>.json` (one per entry)
```json
{
  "inferenceProvider": "gateway",
  "inferenceGatewayBaseUrl": "https://api.deepseek.com/anthropic",
  "inferenceGatewayApiKey": "sk-...",
  "inferenceGatewayAuthScheme": "bearer",
  "inferenceModels": [
    {"name": "deepseek-v4-pro",   "supports1m": true},
    {"name": "deepseek-v4-flash", "supports1m": true}
  ]
}
```

The script writes the entry file and edits `_meta.json` to point at it.
**API key is plaintext** — same as Claude Desktop itself stores it.

## Forward flow

```
1. Pre-flight
     - macOS (Darwin)
     - /Applications/Claude.app exists
     - /usr/bin/jq exists

2. Resolve DEEPSEEK_API_KEY
     a. $DEEPSEEK_API_KEY env var
     b. grep ~/.zshrc, ~/.bashrc, ~/.bash_profile, ~/.profile
     c. osascript display dialog (hidden answer) — interactive fallback

3. Confirmation gate
     - Print summary, wait for Enter (Ctrl-C aborts)

4. Edit config
     - mkdir -p ~/Library/Application Support/Claude-3p/configLibrary
     - Read existing _meta.json (or initialize {"appliedId": null, "entries": []})
     - Find entry with name == "dsclaude-desktop"; if found reuse its id, else
       generate new UUID via `uuidgen`
     - Write <uuid>.json with the gateway config
     - Update _meta.json: ensure entry is in entries[], set appliedId = <uuid>

5. Restart Claude Desktop
     - killall Claude (ignore exit code if not running)
     - sleep 1
     - open -a Claude

6. Print finishing message
     - Tell user Claude Desktop is restarting in gateway mode
     - Note: Chat mode is disabled in third-party mode (Cowork + Code only).
       To use Chat: pick "Continue with Anthropic" in launch chooser, or
       toggle "Skip login-mode chooser" off in the Configure Third-Party
       Inference dialog.
```

## Idempotency

| State on entry | Behavior |
|---|---|
| Fresh (no Claude-3p dir) | Create dir + entry + _meta, apply |
| `appliedId: null` | Re-apply existing or new entry |
| Already DeepSeek (this script's entry) | Overwrite entry's content (refresh key, models) |
| Other gateway entry applied (set up via UI) | Add ours alongside, set appliedId to ours |

## Error handling

- All file edits via temp file + atomic mv (so a Ctrl-C mid-write can't corrupt JSON)
- jq parse failure on existing _meta.json → bail with message pointing at file
- mkdir / write permission failure → bail with the actual error
- killall Claude failure (not running) → ignored (open -a still works)

## Testing

No automated tests. Manual acceptance:

1. **Fresh state (no Claude-3p dir)**: `rm -rf "~/Library/Application Support/Claude-3p"`, then run `./dsclaude-desktop`. Verify Claude Desktop boots in Cowork 3P / Gateway mode and chat with DeepSeek works.
2. **Re-apply (idempotency)**: run `./dsclaude-desktop` again. Verify same UUID is reused (no second entry in `entries[]`), key/models refreshed.
3. **Switch to Anthropic via Claude UI**: at Claude Desktop's launch chooser pick "Continue with Anthropic" — Chat should be available. Re-run `./dsclaude-desktop` to switch back to gateway.
4. **Missing API key**: unset `DEEPSEEK_API_KEY` and remove from rc files, run script, verify osascript dialog fires.

## File layout

```
xxclaude/
├── dsclaude                    # existing — Claude Code → DeepSeek
├── dsclaude-desktop            # NEW — Claude Desktop → DeepSeek (~60 lines)
└── docs/superpowers/
    ├── specs/2026-04-28-dsclaude-desktop-design.md   # this file
    └── plans/2026-04-28-dsclaude-desktop.md          # implementation plan
```

## Discovery notes

The original v1 spec assumed UI driving via osascript, with 9 implementation
tasks and 150 lines of script. Live exploration revealed:

1. The "Configure Third-Party Inference" dialog is **inside the Electron WebView**,
   not native AppKit — System Events / AppleScript cannot drive it.
2. But the resulting config is **plaintext JSON** in
   `~/Library/Application Support/Claude-3p/configLibrary/`, not encrypted via
   Electron `safeStorage`. Direct file edits work.
3. Claude Desktop's "connection test" hits `https://api.deepseek.com/` (root,
   no path) and gets 404. This is benign — real chat traffic uses `/anthropic`.
4. With third-party inference active, Claude Desktop hides the **Chat** mode;
   only Cowork (3P) and Code modes are available.

Pivoting from UI driving to file editing collapses the script to ~60 lines and
the implementation plan to 3 tasks. The `--revert` command was also removed
because Claude Desktop's launch chooser already lets users switch between
gateway mode and Anthropic mode without touching the config file.

### Gotchas discovered during implementation

After the spec was approved, three more Claude Desktop quirks turned up
during testing. They're all handled in the script but worth noting for
anyone reading the source:

1. **Entry JSON cannot end with a trailing newline.** Claude Desktop's parser
   throws "unknown config id" if the file ends with `}\n` instead of `}`. jq
   always emits a trailing newline, so the script captures jq output via
   command substitution (`$(...)` strips trailing newlines) and writes via
   `printf '%s'`.
2. **UUIDs must be lowercase.** macOS `uuidgen` returns uppercase UUIDs;
   Claude's GUI writes lowercase. Even though `_meta.json` references the
   filename and the file is on disk, Claude's "known config id" check appears
   to be case-sensitive. The script lowercases via `tr 'A-Z' 'a-z'` defensively.
3. **File permissions must be 0600.** Claude's GUI writes config files with
   0600 perms (the file contains a plaintext API key). The script `chmod 600`
   the temp file before atomic-mv to match.
4. **Developer Mode is a hard prerequisite.** Third-party inference is gated
   behind it. The script checks `~/Library/Application Support/Claude/developer_settings.json`
   for `allowDevTools: true` and fails with instructions if missing.

## References

- [DeepSeek Anthropic-compatible API](https://api-docs.deepseek.com/guides/anthropic_api)
- Existing sibling: `xxclaude/dsclaude`
