# dsclaude-desktop — Claude Desktop ↔ DeepSeek Configurator

**Date**: 2026-04-28
**Status**: Approved (rewritten after live discovery — see "Discovery notes" at end)

## Goal

A single bash script that switches Claude Desktop's third-party inference backend
to DeepSeek, with a `--revert` mode to restore the default (no third-party).
Companion to the existing `dsclaude` script (which targets Claude Code, not the
desktop app).

## Scope

**In scope**
- macOS only
- Forward: configure Claude Desktop to use DeepSeek as gateway
- Reverse: clear gateway, restore default
- Restart Claude Desktop so changes take effect

**Out of scope (YAGNI)**
- Windows / Linux
- Multiple gateway backends (DeepSeek / Qwen / aihubmix toggle)
- Recovery from a corrupted Claude Desktop config (user can reset via `Reset App Data…`)

**Important user-facing limitation (not fixable by this script)**
- Once any third-party gateway is configured, Claude Desktop's **Chat** mode is
  unavailable — only **Cowork (3P)** and **Code** modes work, because Chat
  depends on Anthropic-hosted features (memory, projects, artifacts). Document
  this in the script's help text so users aren't surprised.

## User-facing CLI

```
dsclaude-desktop            # configure: switch Claude Desktop to DeepSeek
dsclaude-desktop --revert   # revert: clear gateway, restore default
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
     - Note: Chat mode is disabled in third-party mode (Cowork + Code only)
     - Run `dsclaude-desktop --revert` to undo
```

## Revert flow

```
1. Pre-flight (same as forward)

2. Confirmation gate

3. Edit config
     - If _meta.json doesn't exist: nothing to do, print "already vanilla"
     - Else: set appliedId = null (keep entries[] intact for easy re-apply)

4. Restart Claude Desktop

5. Print finishing message
```

## Idempotency

| State on entry | Forward | Revert |
|---|---|---|
| Fresh (no Claude-3p dir) | Create dir + entry + _meta, apply | No-op + message |
| `appliedId: null` | Re-apply existing or new entry | No-op + message |
| Already DeepSeek (this script's entry) | Overwrite entry's content (refresh key, models) | Set appliedId = null |
| Other gateway entry applied (set up via UI) | Add ours alongside, set appliedId to ours | Set appliedId = null |

## Error handling

- All file edits via temp file + atomic mv (so a Ctrl-C mid-write can't corrupt JSON)
- jq parse failure on existing _meta.json → bail with message pointing at file
- mkdir / write permission failure → bail with the actual error
- killall Claude failure (not running) → ignored (open -a still works)

## Testing

No automated tests. Manual acceptance:

1. **Fresh state (no Claude-3p dir)**: `rm -rf "~/Library/Application Support/Claude-3p"`, then run `./dsclaude-desktop`. Verify Claude Desktop boots in Cowork 3P / Gateway mode and chat with DeepSeek works.
2. **Revert**: run `./dsclaude-desktop --revert`. Claude Desktop should boot in normal Anthropic mode with Chat available.
3. **Re-apply**: run `./dsclaude-desktop` again. Verify back to gateway mode without re-prompting (key picked up from env or rc).
4. **Idempotent revert**: run `./dsclaude-desktop --revert` twice in a row. Second run should print "already vanilla" and no-op.
5. **Missing API key**: unset `DEEPSEEK_API_KEY` and remove from rc files, run script, verify osascript dialog fires.

## File layout

```
xxclaude/
├── dsclaude                    # existing — Claude Code → DeepSeek
├── dsclaude-desktop            # NEW — Claude Desktop → DeepSeek (~80 lines)
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

Pivoting from UI driving to file editing collapses the script to ~80 lines and
the implementation plan to 4 tasks.

## References

- [DeepSeek Anthropic-compatible API](https://api-docs.deepseek.com/guides/anthropic_api)
- Existing sibling: `xxclaude/dsclaude`
