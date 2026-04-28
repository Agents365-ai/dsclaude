# xxclaude — 面向其他模型后端的 Claude Code & Claude Desktop 启动器

[English](README.md)

一套小巧的 Shell 脚本，让 [Claude Code](https://claude.ai/code) 和 Claude Desktop 指向非 Anthropic 的模型后端。

## 脚本列表

| 脚本 | Agent | 后端 | 模型 |
|------|-------|------|------|
| **[dsclaude](dsclaude)** | Claude Code (CLI) | DeepSeek API（Anthropic 兼容端点） | `deepseek-v4-pro[1m]`（默认，统一推理）· `deepseek-v4-flash[1m]`（快速 / haiku 档位） |
| **[dsclaude-desktop](dsclaude-desktop)** | Claude Desktop (macOS GUI) | DeepSeek API（Anthropic 兼容端点） | `deepseek-v4-pro` · `deepseek-v4-flash`（两者均启用 1M 上下文） |

`dsclaude` 会在 Claude Code 的 `/model` 选择器中暴露备选模型，支持会话中热切换；同时设置 `ANTHROPIC_DEFAULT_HAIKU_MODEL`，让后台/轻量任务走快模型；并支持可选的环境变量覆盖上下文窗口和输出 token 上限。

`dsclaude-desktop` 把 gateway 配置写入 Claude Desktop 的第三方推理配置目录并重启 App。运行后 Claude Desktop 进入 Cowork (3P) / Code 模式跑 DeepSeek，要切回 Anthropic 直接在启动选择器里点 "Continue with Anthropic" 即可（无需 `--revert`）。

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

### dsclaude-desktop

配置 **Claude Desktop** 的推理后端指向 DeepSeek，原理是直接编辑 `~/Library/Application Support/Claude-3p/configLibrary/` 下的 JSON 配置文件并重启 App。**仅支持 macOS。**

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # 添加到 ~/.zshrc 或 ~/.bashrc

./dsclaude-desktop      # 配置并重启 Claude Desktop
./dsclaude-desktop -h   # 帮助
```

脚本会在 Claude Desktop 的 third-party config 中写入一个名为 `dsclaude-desktop` 的条目（与你通过 GUI 配置的其它条目共存），把 `appliedId` 指过去，然后 `killall Claude && open -a Claude` 让改动生效。

> **重要提醒：** 一旦 third-party gateway 启用，Claude Desktop 的 **Chat** 模式就不可用了（Chat 依赖 Anthropic 托管的服务）—— 只能用 **Cowork (3P)** 和 **Code** 模式。要回到 Anthropic Chat：在 Claude Desktop 启动选择器里点 "Continue with Anthropic"。再跑一遍 `dsclaude-desktop` 就能切回 DeepSeek。

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
