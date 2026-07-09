---
title: dsclaude
description: Claude Code & Claude Desktop launchers for alternative backends
---

**English** · [中文](zh.html) · [GitHub](https://github.com/Agents365-ai/dsclaude)

A collection of launchers and configurators that point [Claude Code](https://claude.ai/code) and Claude Desktop at third-party model backends (DeepSeek, Xiaomi MiMo, etc.).

**Author:** [Agents365-ai](https://github.com/Agents365-ai) · [Bilibili](https://space.bilibili.com/441831884)

---

## Tools

| Tool | What it does | Platform | Backend |
|------|-------------|----------|---------|
| **[dsclaude](https://github.com/Agents365-ai/dsclaude/blob/main/dsclaude)** | Claude Code CLI launcher | macOS / Linux | DeepSeek |
| **[mmclaude](https://github.com/Agents365-ai/dsclaude/blob/main/mmclaude)** | Claude Code CLI launcher | macOS / Linux | Xiaomi MiMo |
| **[dsclaude-desktop](https://github.com/Agents365-ai/dsclaude/blob/main/dsclaude-desktop)** | Claude Desktop GUI configurator | macOS | DeepSeek |
| **[dsclaude-desktop.ps1](https://github.com/Agents365-ai/dsclaude/blob/main/dsclaude-desktop.ps1)** | Claude Desktop GUI configurator | Windows | DeepSeek |
| **[skills/deepseek-vision](https://github.com/Agents365-ai/dsclaude/tree/main/skills/deepseek-vision)** | Vision skill (zero deps) | macOS / Linux | DashScope Qwen |
| **[dsvision-mcp](https://github.com/Agents365-ai/dsclaude/blob/main/dsvision-mcp)** | Vision MCP server | macOS / Linux | DashScope Qwen |

---

## Quick start on macOS

```bash
git clone https://github.com/Agents365-ai/dsclaude.git
cd dsclaude
chmod +x dsclaude
./dsclaude
```

---

## dsclaude — Claude Code on DeepSeek

Follows the [DeepSeek Anthropic API](https://api-docs.deepseek.com/guides/anthropic_api) guide.

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # add to ~/.zshrc

dsclaude                 # default: deepseek-v4-pro (full reasoning)
dsclaude fast            # deepseek-v4-flash (cheaper / faster)
dsclaude long            # request 1M context window
dsclaude long fast       # 1M + flash
```

Sets the DeepSeek-recommended env vars (`ANTHROPIC_BASE_URL`, model mappings, `CLAUDE_CODE_EFFORT_LEVEL=max`), and exposes the alternate model in Claude Code's `/model` picker. Override context window via `DSCLAUDE_MAX_TOKENS` and effort via `DSCLAUDE_EFFORT`.

> Both models natively support 1M-token context. The `[1m]` suffix (e.g. `deepseek-v4-pro[1m]`) is required in Claude Code — `dsclaude` sets it automatically.

---

## mmclaude — Claude Code on Xiaomi MiMo

```bash
export MIMO_API_KEY=sk-xxxxxxxxxxxxxxxxxx       # pay-as-you-go
# or
export MIMO_API_KEY=tp-xxxxxxxxxxxxxxxxxx       # Token Plan

mmclaude                  # start on mimo-v2.5-pro
mmclaude update           # git pull
```

Auto-detects base URL from the key prefix (`sk-*` → public, `tp-*` → Token Plan); override with `MIMO_BASE_URL`. Sets all four model slots to `mimo-v2.5-pro` and unsets `ANTHROPIC_API_KEY` (per MiMo docs).

---

## dsclaude-desktop — Claude Desktop GUI configurator

One-command configurator for Claude Desktop's built-in **Third-Party Inference** feature (Developer menu), pre-filled for DeepSeek.

### Prerequisites

1. Claude Desktop installed ([claude.ai/download](https://claude.ai/download))
2. Developer Mode enabled (Help → Troubleshooting → Enable Developer Mode, once)
3. `DEEPSEEK_API_KEY` environment variable set

### Usage (macOS)

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx
./dsclaude-desktop        # configure and restart
./dsclaude-desktop -h     # help
```

Generates an entry under `~/Library/Application Support/Claude-3p/configLibrary/`, sets it as `appliedId` in `_meta.json`, then restarts the app. Existing GUI-added entries are preserved.

### Switching modes

Claude Desktop's launch chooser handles Anthropic ↔ Gateway switching natively — no `--revert` flag. Click your profile → **Disconnect** (or sign out), then pick the other option at next launch.

> Classic **Chat** (claude.ai-style) is unavailable in Gateway mode — it depends on Anthropic-hosted features not exposed via the inference API. Switch back to Anthropic mode to use it.

### Usage (Windows)

```powershell
$env:DEEPSEEK_API_KEY = "sk-xxxxxxxxxxxxxxxxxx"
pwsh ./dsclaude-desktop.ps1
```

Unlike macOS, Developer Mode is **auto-enabled** by the script — no manual GUI toggle needed.

Config path: `%LOCALAPPDATA%\Claude-3p\configLibrary\` (for Store/MSIX installs, the script also writes to the sandboxed package path as a fallback).

Tested on Windows 11 with Claude Desktop 1.7196 (Windows Store, arm64).

---

## deepseek-vision skill — Vision (zero-dependency)

Gives text-only agents (like DeepSeek) the ability to "see" images. When the agent encounters an image, it calls `analyze-image`, which sends it to Qwen3.6-Flash and returns a text description.

```bash
export DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxxxx
./skills/deepseek-vision/analyze-image /path/to/screenshot.png "What error is shown?"
./skills/deepseek-vision/analyze-image https://example.com/diagram.png
```

Works with any agent that loads `SKILL.md` (Claude Code, Cowork, etc.). Default model `qwen3.6-flash`; override via `DSVISION_MODEL` and `DSVISION_BASE_URL`.

> **Limitation**: requires a file path or URL — inline images (drag-drop, paste, "+ → Add files or photos") aren't supported. Use **dsvision-mcp** below for that.

---

## dsvision-mcp — Vision (MCP server)

Same functionality as the skill above, but runs as an MCP server — bypassing two Cowork sandbox limitations:

1. **Network egress** — the skill's DashScope API calls are firewalled inside Cowork's VM; the MCP server runs outside it
2. **Inline images** — auto-picks the latest cached image from `~/.claude/image-cache/`, so drag-drop/paste/"+" workflows work (macOS only; Windows Cowork doesn't cache inline images to disk)

### Setup

```bash
pip3 install fastmcp requests
export DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # add to ~/.zshrc
cd /path/to/dsclaude && pwd    # note the absolute path
```

Add to the MCP config file matching your mode:

| Mode | Config file |
|------|-------------|
| 3P/Gateway (DeepSeek via `dsclaude-desktop`) | `~/Library/Application Support/Claude-3p/claude_desktop_config.json` |
| Standard Anthropic | `~/Library/Application Support/Claude/claude_desktop_config.json` |

```json
{
  "mcpServers": {
    "dsvision": {
      "command": "/absolute/path/dsclaude/dsvision-mcp"
    }
  }
}
```

Restart Claude Desktop. The `analyze_image` tool appears automatically.

### Usage

```
analyze_image()                           # auto: latest cached image
analyze_image(image_path="/abs/path/foo.png")
analyze_image(focus="What error is shown?")
```

### Troubleshooting

| Symptom | Check |
|---------|-------|
| Tool doesn't appear | Wrong config file path / invalid JSON (validate with `python3 -m json.tool`) |
| Tool errors | `DASHSCOPE_API_KEY` not set |
| `ModuleNotFoundError` | Use `pip3` not `pip` |
| Image not found | Pass absolute path, or check `~/.claude/image-cache/` exists |

### Skill vs MCP: which to use

| Scenario | Use |
|----------|-----|
| Claude Code (CLI), explicit paths | `skills/deepseek-vision` (zero deps) |
| Cowork / Desktop with inline images | `dsvision-mcp` (only option that works) |
| Cowork with explicit paths, sandbox tweaks OK | either |

---

## Community

- **Discord:** <https://discord.gg/79JF5Atuk>
- **WeChat:** scan the QR code below

<p align="center">
  <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/agents365ai_wechat_1.png" width="200" alt="WeChat Community Group">
</p>

## Support

If these scripts save you time, consider supporting the author:

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/wechat-pay.png" width="150" alt="WeChat Pay"><br><b>WeChat Pay</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/alipay.png" width="150" alt="Alipay"><br><b>Alipay</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/buymeacoffee.png" width="150" alt="Buy Me a Coffee"><br><b>Buy Me a Coffee</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/awarding/award.gif" width="150" alt="Give a Reward"><br><b>Give a Reward</b></td>
  </tr>
</table>

## License

[CC BY-NC 4.0](https://github.com/Agents365-ai/dsclaude/blob/main/LICENSE.md) — free for non-commercial use. **Commercial use requires permission.**
