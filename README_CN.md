# xxclaude — 面向其他模型后端的 Claude Code 启动器

[English](README.md)

一套小巧的 Shell 脚本，让 [Claude Code](https://claude.ai/code) 指向非 Anthropic 的模型后端，同时保留原生 TUI、工具链和 `/model` 切换器。

## 脚本列表

| 脚本 | Agent | 后端 | 模型 |
|------|-------|------|------|
| **[dsclaude](dsclaude)** | Claude Code | DeepSeek API（Anthropic 兼容端点） | `deepseek-v4-pro[1m]`（默认，统一推理）· `deepseek-v4-flash[1m]`（快速 / haiku 档位） |

`dsclaude` 会在 Claude Code 的 `/model` 选择器中暴露备选模型，支持会话中热切换；同时设置 `ANTHROPIC_DEFAULT_HAIKU_MODEL`，让后台/轻量任务走快模型；并支持可选的环境变量覆盖上下文窗口和输出 token 上限。

## 兼容性

| 平台 | 支持状态 |
|------|----------|
| macOS | 原生支持，完全可用 |
| Linux (Ubuntu 等) | 兼容 — 依赖 `bash` 和标准 POSIX 工具（系统自带） |
| Windows | 不原生支持 — 可通过 [WSL](https://learn.microsoft.com/zh-cn/windows/wsl/) 或 Git Bash 运行 |

## 快速开始

```bash
git clone https://github.com/Agents365-ai/xxclaude.git
cd xxclaude
chmod +x dsclaude
```

可选 — 设为全局命令：

```bash
sudo mv dsclaude /usr/local/bin/
```

### dsclaude

遵循 DeepSeek 官方指南：[Integrate with Coding Agents](https://api-docs.deepseek.com/guides/coding_agents) / [Anthropic API](https://api-docs.deepseek.com/guides/anthropic_api)。

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # 添加到 ~/.zshrc 或 ~/.bashrc

dsclaude                 # 以 deepseek-v4-pro 启动（默认，完整推理能力）
dsclaude fast            # 以 deepseek-v4-flash[1m] 启动（更便宜/更快）
dsclaude long            # 申请 1M 上下文窗口（1,048,576 tokens）
dsclaude long fast       # 1M + flash
```

脚本会自动按 DeepSeek 官方建议导出全套环境变量：`ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic`、Opus/Sonnet/Haiku 模型映射、`CLAUDE_CODE_SUBAGENT_MODEL` 以及 `CLAUDE_CODE_EFFORT_LEVEL=max`（可用 `DSCLAUDE_EFFORT` 覆盖）。

会话中切换：`/model deepseek-v4-flash[1m]` ↔ `/model deepseek-v4-pro[1m]`。

> **注意：** `deepseek-v4-pro` 和 `deepseek-v4-flash` 均原生支持 1M token 上下文窗口。在 Claude Code 中，两个模型都需要加 `[1m]` 后缀来开启（`deepseek-v4-pro[1m]`、`deepseek-v4-flash[1m]`）。`dsclaude` 已自动完成此设置。

## 开源协议

MIT

## 赞赏支持

如果这些脚本为你节省了时间，欢迎支持作者：

<table>
  <tr>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/wechat-pay.png" width="180" alt="微信支付">
      <br>
      <b>微信支付</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/alipay.png" width="180" alt="支付宝">
      <br>
      <b>支付宝</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/buymeacoffee.png" width="180" alt="Buy Me a Coffee">
      <br>
      <b>Buy Me a Coffee</b>
    </td>
    <td align="center">
      <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/awarding/award.gif" width="180" alt="打赏">
      <br>
      <b>打赏鼓励</b>
    </td>
  </tr>
</table>

## 作者

**Agents365-ai**

- 哔哩哔哩：https://space.bilibili.com/441831884
- GitHub：https://github.com/Agents365-ai
