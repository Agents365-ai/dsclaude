# xxclaude — Claude Code launchers for alternative backends

[中文文档](README_CN.md)

A small collection of shell scripts that point [Claude Code](https://claude.ai/code) at non-Anthropic model backends while keeping the native TUI, tools, and `/model` switcher.

## Scripts

| Script | Agent | Backend | Models |
|--------|-------|---------|--------|
| **[dsclaude](dsclaude)** | Claude Code | DeepSeek API (Anthropic-compatible endpoint) | `deepseek-v4-pro[1m]` (default, unified reasoning) · `deepseek-v4-flash[1m]` (fast / haiku tier) |

`dsclaude` exposes the alternate model in Claude Code's `/model` picker so you can hot-swap mid-session, sets `ANTHROPIC_DEFAULT_HAIKU_MODEL` so background/cheap tasks route to the fast model, and honors optional env overrides for context window and output token limits.

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
