# xxclaude — Claude Code launchers for alternative backends

[中文文档](README_CN.md)

A small collection of shell scripts that point [Claude Code](https://claude.ai/code) at non-Anthropic model backends while keeping the native TUI, tools, and `/model` switcher.

## Scripts

| Script | Backend | Models |
|--------|---------|--------|
| **[dsclaude](dsclaude)** | DeepSeek API (Anthropic-compatible endpoint) | `deepseek-chat` (default) · `deepseek-reasoner` (thinking) |
| **[qwclaude](qwclaude)** | Local Ollama (via embedded Anthropic↔Ollama proxy) | `qwen3.6-27b` (dense default) · `qwen3.6:35b-a3b` (MoE thinking) |

Both scripts:

- Expose the alternate model in Claude Code's `/model` picker so you can hot-swap mid-session.
- Set `ANTHROPIC_DEFAULT_HAIKU_MODEL` so background/cheap tasks route to the fast model.
- Honor optional env overrides for context window and output token limits.

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
chmod +x dsclaude qwclaude
```

Make them globally available (optional):

```bash
sudo mv dsclaude qwclaude /usr/local/bin/
```

### dsclaude

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # add this line to ~/.zshrc or ~/.bashrc

dsclaude                 # start on deepseek-chat (fast default)
dsclaude think           # start on deepseek-reasoner (thinking mode)
dsclaude long            # request a 512K context window
dsclaude long think      # 512K + reasoner
```

In-session: `/model deepseek-reasoner` ↔ `/model deepseek-chat`.

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
