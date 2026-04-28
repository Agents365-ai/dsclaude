# dsclaude — Claude Code & Claude Desktop launchers for alternative backends

[中文文档](README_CN.md)

A small collection of shell scripts that point [Claude Code](https://claude.ai/code) and Claude Desktop at non-Anthropic model backends.

## Scripts

| Script | Agent | Platform | Backend | Models |
|--------|-------|----------|---------|--------|
| **[dsclaude](dsclaude)** | Claude Code (CLI) | macOS / Linux | DeepSeek API (Anthropic-compatible endpoint) | `deepseek-v4-pro[1m]` (default, unified reasoning) · `deepseek-v4-flash[1m]` (fast / haiku tier) |
| **[dsclaude-desktop](dsclaude-desktop)** | Claude Desktop (GUI) | macOS | DeepSeek API (Anthropic-compatible endpoint) | `deepseek-v4-pro` · `deepseek-v4-flash` (1M context on both) |
| **[dsclaude-desktop.ps1](dsclaude-desktop.ps1)** | Claude Desktop (GUI) | Windows (untested) | DeepSeek API (Anthropic-compatible endpoint) | same as above |
| **[skills/deepseek-vision](skills/deepseek-vision/)** | skill (any agent that loads SKILL.md) | macOS / Linux | DashScope (Anthropic / OpenAI-compatible) | `qwen3.6-flash` (default vision) |

`dsclaude` exposes the alternate model in Claude Code's `/model` picker so you can hot-swap mid-session, sets `ANTHROPIC_DEFAULT_HAIKU_MODEL` so background/cheap tasks route to the fast model, and honors optional env overrides for context window and output token limits.

`dsclaude-desktop` is a one-command configurator for Claude Desktop's built-in **Configure Third-Party Inference** feature (Developer menu). It writes the same config that the dialog would write — pre-filled for DeepSeek — and restarts the app. Claude Desktop's launch chooser handles switching back to Anthropic mode natively, so there's no `--revert` flag.

## Compatibility

| Platform | Status |
|----------|--------|
| macOS | Native, fully supported |
| Linux (Ubuntu, etc.) | Compatible — requires `bash` and standard POSIX tools (pre-installed) |
| Windows | Not supported natively — works via [WSL](https://learn.microsoft.com/en-us/windows/wsl/) or Git Bash |

## Quick start

```bash
git clone https://github.com/Agents365-ai/dsclaude.git
cd dsclaude
chmod +x dsclaude
```

Make it globally available (optional):

```bash
sudo mv dsclaude /usr/local/bin/
```

### dsclaude

Follows the official DeepSeek guide: [Integrate with Coding Agents](https://api-docs.deepseek.com/guides/coding_agents) / [Anthropic API](https://api-docs.deepseek.com/guides/anthropic_api).

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # add this line to ~/.zshrc or ~/.bashrc

dsclaude                 # start on deepseek-v4-pro (default, full reasoning)
dsclaude fast            # start on deepseek-v4-flash[1m] (cheaper / faster)
dsclaude long            # request a 1M context window (1,048,576 tokens)
dsclaude long fast       # 1M + flash
```

Sets the DeepSeek-recommended env vars under the hood: `ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic`, Opus/Sonnet/Haiku model mappings, `CLAUDE_CODE_SUBAGENT_MODEL`, and `CLAUDE_CODE_EFFORT_LEVEL=max` (override via `DSCLAUDE_EFFORT`).

In-session: `/model deepseek-v4-flash[1m]` ↔ `/model deepseek-v4-pro[1m]`.

> **Note:** Both `deepseek-v4-pro` and `deepseek-v4-flash` natively support a 1M-token context window. In Claude Code, the `[1m]` suffix is required on each model name to enable it (`deepseek-v4-pro[1m]`, `deepseek-v4-flash[1m]`). `dsclaude` sets this for you.

### dsclaude-desktop

A one-command configurator for Claude Desktop's **built-in third-party inference** feature, pre-filled for DeepSeek.

This is **not** a hack or workaround. Anthropic ships a "Configure Third-Party Inference" dialog inside Claude Desktop (Developer menu) where you can manually point the app at any Anthropic-compatible endpoint. The dialog has six required fields and a model list. `dsclaude-desktop` writes the same JSON config that the dialog would write, then restarts the app — saving you the menu navigation.

#### Prerequisites

1. **Claude Desktop installed** (download from [claude.ai/download](https://claude.ai/download))
2. **Developer Mode enabled** in Claude Desktop
   - Help → Troubleshooting → Enable Developer Mode
   - Only needs to be done once. The script verifies this on each run.
3. **DeepSeek API Key** in `$DEEPSEEK_API_KEY`, your shell rc, or paste at the prompt

#### Usage

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # or add to ~/.zshrc

./dsclaude-desktop      # configure and restart Claude Desktop
./dsclaude-desktop -h   # help
```

What it does:
1. Generates an entry under `~/Library/Application Support/Claude-3p/configLibrary/` with your DeepSeek key, base URL `https://api.deepseek.com/anthropic`, auth scheme `bearer`, and `deepseek-v4-pro` + `deepseek-v4-flash` (1M context) as the model list
2. Sets `appliedId` to your entry in `_meta.json` (existing entries are preserved)
3. Restarts Claude Desktop with `killall Claude && open -a Claude`

#### Switching modes

Claude Desktop's launch chooser handles mode switching natively — no `--revert` flag needed:

<p align="center">
  <img src="docs/images/launch-chooser.png" alt="Claude Desktop launch chooser: Continue with Gateway or Sign in to Anthropic" width="600">
</p>

Even on the Anthropic sign-in page you can swap back to Gateway:

<p align="center">
  <img src="docs/images/sign-in-or-gateway.png" alt="Sign In page with 'Or continue with Gateway' link at bottom" width="600">
</p>

To switch: click your profile in Claude Desktop → **Disconnect** (or sign out) → at next launch, pick the other option.

#### What you get

In Gateway mode the **Cowork** and **Code** modes route to DeepSeek. The model picker shows your masked DeepSeek models:

<p align="center">
  <img src="docs/images/cowork-3p-gateway.png" alt="Cowork mode running on DeepSeek via Gateway" width="700">
</p>

<p align="center">
  <img src="docs/images/code-3p-gateway.png" alt="Code mode in xxclaude project running on DeepSeek via Gateway" width="700">
</p>

> **One feature is unavailable**: classic **Chat** (claude.ai-style conversation). Chat depends on Anthropic-hosted features (memory, projects, artifacts, web search) that aren't part of the inference API surface. To use Chat, switch back to Anthropic mode via the launch chooser.

#### Windows

`dsclaude-desktop.ps1` is the PowerShell port. Same JSON schema, same flow:

```powershell
$env:DEEPSEEK_API_KEY = "sk-xxxxxxxxxxxxxxxxxx"
pwsh ./dsclaude-desktop.ps1
```

Prerequisites mirror the macOS version: Claude Desktop installed, Developer Mode enabled, DeepSeek API key. The script writes to `%APPDATA%\Claude-3p\configLibrary\` instead of `~/Library/Application Support/Claude-3p/configLibrary/`.

> **Untested by the maintainer.** The schema and gotchas were discovered on macOS; Anthropic ships the same Electron app on Windows so they should hold, but please [open an issue](https://github.com/Agents365-ai/dsclaude/issues) if anything misbehaves.

### deepseek-vision skill

A skill for giving DeepSeek (text-only) the ability to "see" images. When the active agent encounters an image file path, it calls `skills/deepseek-vision/analyze-image` which sends the image to **Qwen3.6-Flash** (DashScope) and returns a text description the agent can reason over.

```bash
export DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxxxx

./skills/deepseek-vision/analyze-image /path/to/screenshot.png "What error is shown?"
```

The skill works in any agent that loads `SKILL.md` files (Claude Code, Cowork, etc.). Default model is `qwen3.6-flash`; override via `DSVISION_MODEL=qwen3.6-plus` for higher quality, or `DSVISION_BASE_URL=...` for a different provider.

> Why a skill instead of an MCP server: zero new dependencies (just `bash` + `curl` + `jq`), no daemon process, single markdown + bash file you can read in 2 minutes.

## License

MIT

## Support

If these scripts save you time, consider supporting the author:

<table>
  <tr>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/wechat-pay.png" width="180" alt="WeChat Pay">
      <br>
      <b>WeChat Pay</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/alipay.png" width="180" alt="Alipay">
      <br>
      <b>Alipay</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/buymeacoffee.png" width="180" alt="Buy Me a Coffee">
      <br>
      <b>Buy Me a Coffee</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/awarding/award.gif" width="180" alt="Give a Reward">
      <br>
      <b>Give a Reward</b>
    </td>
  </tr>
</table>

## Author

**Agents365-ai**

- Bilibili: https://space.bilibili.com/441831884
- GitHub: https://github.com/Agents365-ai
