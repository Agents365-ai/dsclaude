# dsclaude — Claude Code & Claude Desktop launchers for alternative backends

[中文文档](README_CN.md)

A collection of launchers and configurators that point [Claude Code](https://claude.ai/code) and Claude Desktop at third-party model backends (DeepSeek, Xiaomi MiMo, etc.).

---

## Tools

| Tool | What it does | Platform | Backend |
|------|-------------|----------|---------|
| **[dsclaude](dsclaude)** | Claude Code CLI launcher | macOS / Linux | DeepSeek |
| **[mmclaude](mmclaude)** | Claude Code CLI launcher | macOS / Linux | Xiaomi MiMo |
| **[qwclaude](qwclaude)** | Claude Code CLI launcher | macOS / Linux | Alibaba Cloud Bailian (Qwen) |
| **[qwclaude.ps1](qwclaude.ps1)** | Claude Code CLI launcher | Windows | Alibaba Cloud Bailian (Qwen) |
| **[dsclaude-desktop](dsclaude-desktop)** | Claude Desktop GUI configurator | macOS | DeepSeek |
| **[dsclaude-desktop.ps1](dsclaude-desktop.ps1)** | Claude Desktop GUI configurator | Windows | DeepSeek |
| **[mmclaude-desktop](mmclaude-desktop)** | Claude Desktop GUI configurator | macOS | Xiaomi MiMo |
| **[mmclaude-desktop.ps1](mmclaude-desktop.ps1)** | Claude Desktop GUI configurator | Windows | Xiaomi MiMo |
| **[qwclaude-desktop](qwclaude-desktop)** | Claude Desktop GUI configurator | macOS | Alibaba Cloud Bailian (Qwen) |
| **[qwclaude-desktop.ps1](qwclaude-desktop.ps1)** | Claude Desktop GUI configurator | Windows | Alibaba Cloud Bailian (Qwen) |
| **[skills/deepseek-vision](skills/deepseek-vision/)** | Vision skill (zero deps) | macOS / Linux | DashScope Qwen |
| **[dsvision-mcp](dsvision-mcp)** | Vision MCP server | macOS / Linux | DashScope Qwen |

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
mmclaude fast             # start on mimo-v2.5 (cheaper / faster flash tier)
mmclaude update           # git pull
```

Auto-detects base URL from the key prefix (`sk-*` → public, `tp-*` → Token Plan); override with `MIMO_BASE_URL`. Main/opus/sonnet slots run `mimo-v2.5-pro` while the haiku and subagent tiers run `mimo-v2.5` (flash); `mmclaude fast` flips the main model to flash, and the other tier is exposed in the `/model` picker for mid-session switching. Unsets `ANTHROPIC_API_KEY` (per MiMo docs). Override the tiers with `MIMO_MODEL` / `MIMO_FLASH_MODEL`.

---

## qwclaude — Claude Code on Alibaba Cloud Bailian (Qwen)

```bash
export QWEN_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # Bailian API Key (or DASHSCOPE_API_KEY)

# macOS / Linux
qwclaude                  # pay-as-you-go, qwen3.7-max (Beijing)
qwclaude fast             # flash tier (qwen3.6-flash) as the main model
qwclaude intl             # pay-as-you-go on the Singapore endpoint
qwclaude coding           # Coding Plan (qwen3.6-plus)
qwclaude token            # Token Plan team edition (qwen3.7-max)
qwclaude update           # git pull

# Windows (PowerShell 7+)
pwsh -File ./qwclaude.ps1 coding
```

Picks the base URL and model lineup per billing plan: pay-as-you-go / Token Plan run `qwen3.7-max` (main/opus/sonnet) with `qwen3.6-flash` on the haiku + subagent tiers; Coding Plan runs `qwen3.6-plus` (its only model). `fast` flips the main model to flash, and the other tier is exposed in the `/model` picker. Sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1` and unsets `ANTHROPIC_API_KEY` to keep traffic on Bailian (avoids the `api.anthropic.com` connection error). Override via `QWEN_PLAN` / `QWEN_REGION` / `QWEN_MODEL` / `QWEN_FLASH_MODEL` / `QWEN_BASE_URL`.

> The Windows port (`qwclaude.ps1`) requires PowerShell 7+ (`winget install Microsoft.PowerShell`) — run it with `pwsh -File`.

---

## dsclaude-desktop — Claude Desktop GUI configurator

One-command configurator for Claude Desktop's built-in **Third-Party Inference** feature (Developer menu), pre-filled for DeepSeek.

### Prerequisites

1. Claude Desktop installed ([claude.ai/download](https://claude.ai/download))
2. Developer Mode enabled (Help → Troubleshooting → Enable Developer Mode, once)
3. `DEEPSEEK_API_KEY` environment variable set

### Usage

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx
./dsclaude-desktop        # configure and restart
./dsclaude-desktop -h     # help
```

Generates an entry under `~/Library/Application Support/Claude-3p/configLibrary/`, sets it as `appliedId` in `_meta.json`, then restarts the app. Existing GUI-added entries are preserved.

### Switching modes

Claude Desktop's launch chooser handles Anthropic ↔ Gateway switching natively — no `--revert` flag. Click your profile → **Disconnect** (or sign out), then pick the other option at next launch.

> Classic **Chat** (claude.ai-style) is unavailable in Gateway mode — it depends on Anthropic-hosted features not exposed via the inference API. Switch back to Anthropic mode to use it.

### Windows

```powershell
$env:DEEPSEEK_API_KEY = "sk-xxxxxxxxxxxxxxxxxx"
pwsh ./dsclaude-desktop.ps1
```

Writes to `%APPDATA%\Claude-3p\configLibrary\`. > Untested by the maintainer — please [open an issue](https://github.com/Agents365-ai/dsclaude/issues) if anything misbehaves.

---
Prerequisites: Claude Desktop installed (Store or standard), DeepSeek API key. Unlike macOS, Developer Mode is **auto-enabled** by the script — no manual GUI toggle needed.

Config path: `%LOCALAPPDATA%\Claude-3p\configLibrary\` (for Store/MSIX installs, the script also writes to the sandboxed package path as a fallback).

Tested on Windows 11 with Claude Desktop 1.7196 (Windows Store, arm64).

---

## mmclaude-desktop — Claude Desktop on Xiaomi MiMo

Same configurator as `dsclaude-desktop`, pre-filled for Xiaomi MiMo. Reads `MIMO_API_KEY` and auto-detects the base URL from the key prefix (`tp-*` → Token Plan, else pay-as-you-go; override with `MIMO_BASE_URL`). Configures `mimo-v2.5-pro` + `mimo-v2.5`.

```bash
export MIMO_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # or tp-... for Token Plan
./mmclaude-desktop        # configure and restart (macOS)
./mmclaude-desktop -h     # help

# Windows (PowerShell)
$env:MIMO_API_KEY = "sk-xxxxxxxxxxxxxxxxxx"
pwsh ./mmclaude-desktop.ps1
```

---

## qwclaude-desktop — Claude Desktop on Alibaba Cloud Bailian (Qwen)

Same configurator, with per-plan base URL, models, and key variable. Pay-as-you-go (`DASHSCOPE_API_KEY`) and Token Plan (`DASHSCOPE_TP_API_KEY`) configure `qwen3.7-max` + `qwen3.6-flash`; Coding Plan (`DASHSCOPE_CP_API_KEY`) configures `qwen3.6-plus`.

```bash
export DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxxxx       # pay-as-you-go
export DASHSCOPE_CP_API_KEY=sk-xxxxxxxxxxxxxxxxxx    # Coding Plan
export DASHSCOPE_TP_API_KEY=sk-xxxxxxxxxxxxxxxxxx    # Token Plan

./qwclaude-desktop            # pay-as-you-go (Beijing), then restart
./qwclaude-desktop intl       # pay-as-you-go, Singapore endpoint
./qwclaude-desktop coding     # Coding Plan
./qwclaude-desktop token      # Token Plan

# Windows (PowerShell)
pwsh ./qwclaude-desktop.ps1 -Plan coding
```

> The `.ps1` Windows ports mirror `dsclaude-desktop.ps1` and are **untested by the maintainer** — please [open an issue](https://github.com/Agents365-ai/dsclaude/issues) if anything misbehaves. Both configurators set `unstableDisableModelVerification` so Claude Desktop accepts the non-Anthropic model names, and (like `dsclaude-desktop`) disable Chat mode while the gateway is active.

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

Join us for help, Q&A, and updates:

- **Discord:** https://discord.gg/79JF5Atuk
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

## Author

**Agents365-ai** · [Bilibili](https://space.bilibili.com/441831884) · [GitHub](https://github.com/Agents365-ai)

## License

MIT
