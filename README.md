# xxclaude — Claude Code launchers for alternative backends

[中文文档](README_CN.md)

A small collection of shell scripts that point [Claude Code](https://claude.ai/code) at non-Anthropic model backends while keeping the native TUI, tools, and `/model` switcher.

## Scripts

| Script | Agent | Backend | Models |
|--------|-------|---------|--------|
| **[dsclaude](dsclaude)** | Claude Code | DeepSeek API (Anthropic-compatible endpoint) | `deepseek-v4-pro` (default, unified reasoning) · `deepseek-v4-flash` (fast / haiku tier) |
| **[dscodex](dscodex)** | OpenAI Codex CLI | DeepSeek API (OpenAI-compatible endpoint) | `deepseek-v4-pro` (default) · `deepseek-v4-flash` (fast) |
| **[qwclaude](qwclaude)** | Claude Code | Local Ollama (via embedded Anthropic↔Ollama proxy) | `qwen3.6-27b` (dense default) · `qwen3.6:35b-a3b` (MoE thinking) |

The Claude Code launchers (`dsclaude`, `qwclaude`):

- Expose the alternate model in Claude Code's `/model` picker so you can hot-swap mid-session.
- Set `ANTHROPIC_DEFAULT_HAIKU_MODEL` so background/cheap tasks route to the fast model.
- Honor optional env overrides for context window and output token limits.

`dscodex` registers DeepSeek as a Codex `model_providers` entry via inline `-c` overrides — it never touches `~/.codex/config.toml`, so running it alongside the default OpenAI Codex setup is safe.

## Compatibility

| Platform | Status |
|----------|--------|
| macOS | Native, fully supported |
| Linux (Ubuntu, etc.) | Compatible — requires `bash` and standard POSIX tools (pre-installed) |
| Windows | Not supported natively — works via [WSL](https://learn.microsoft.com/en-us/windows/wsl/) or Git Bash |

## Quick start

```bash
git clone https://github.com/Agents365-ai/xxclaude.git
cd xxclaude
chmod +x dsclaude dscodex qwclaude
```

Make them globally available (optional):

```bash
sudo mv dsclaude dscodex qwclaude /usr/local/bin/
```

### dsclaude

Follows the official DeepSeek guide: [Integrate with Coding Agents](https://api-docs.deepseek.com/guides/coding_agents) / [Anthropic API](https://api-docs.deepseek.com/guides/anthropic_api).

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # add this line to ~/.zshrc or ~/.bashrc

dsclaude                 # start on deepseek-v4-pro (default, full reasoning)
dsclaude fast            # start on deepseek-v4-flash (cheaper / faster)
dsclaude long            # request a 1M context window (1,048,576 tokens)
dsclaude long fast       # 1M + flash
```

Sets the DeepSeek-recommended env vars under the hood: `ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic`, Opus/Sonnet/Haiku model mappings, `CLAUDE_CODE_SUBAGENT_MODEL`, and `CLAUDE_CODE_EFFORT_LEVEL=max` (override via `DSCLAUDE_EFFORT`).

In-session: `/model deepseek-v4-flash` ↔ `/model deepseek-v4-pro`.

### dscodex

Runs [OpenAI Codex CLI](https://github.com/openai/codex) against DeepSeek's OpenAI-compatible endpoint. Fully self-contained — does **not** modify `~/.codex/config.toml`.

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # same key as dsclaude; add to ~/.zshrc or ~/.bashrc

dscodex                  # start on deepseek-v4-pro (default)
dscodex fast             # start on deepseek-v4-flash (cheaper / faster)
dscodex exec "write a quick script that ..."   # any remaining args forward to codex
```

Under the hood it injects the DeepSeek provider via `codex -c 'model_providers.deepseek={...}'` with `base_url=https://api.deepseek.com/v1` and `wire_api="chat"`. DeepSeek's OpenAI endpoint only speaks Chat Completions, so Codex features that require the Responses API (reasoning-effort dial, richer tool streaming) may be degraded.

### qwclaude

Prerequisites — Ollama running locally with the models already pulled:

```bash
ollama pull qwen3.6-27b        # dense 27B, fast default
ollama pull qwen3.6:35b-a3b    # MoE 35B (3B active), thinking mode
```

```bash
qwclaude                 # start on qwen3.6-27b (dense, fast default)
qwclaude think           # start on qwen3.6:35b-a3b (MoE thinking mode)
```

Defaults to a **256K context window** (`num_ctx=262144` + `CLAUDE_CODE_MAX_CONTEXT_TOKENS=262144` + `DISABLE_COMPACT=1`). Override with `QWCLAUDE_CTX=131072 qwclaude`.

In-session: `/model qwen3.6-27b` ↔ `/model qwen3.6:35b-a3b`.

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
