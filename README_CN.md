# dsclaude — 面向其他模型后端的 Claude Code & Claude Desktop 启动器

[English](README.md)

一套小巧的 Shell 脚本，让 [Claude Code](https://claude.ai/code) 和 Claude Desktop 指向非 Anthropic 的模型后端。

## 脚本列表

| 脚本 | Agent | 平台 | 后端 | 模型 |
|------|-------|------|------|------|
| **[dsclaude](dsclaude)** | Claude Code (CLI) | macOS / Linux | DeepSeek API（Anthropic 兼容端点） | `deepseek-v4-pro[1m]`（默认，统一推理）· `deepseek-v4-flash[1m]`（快速 / haiku 档位） |
| **[dsclaude-desktop](dsclaude-desktop)** | Claude Desktop (GUI) | macOS | DeepSeek API（Anthropic 兼容端点） | `deepseek-v4-pro` · `deepseek-v4-flash`（均启用 1M 上下文） |
| **[dsclaude-desktop.ps1](dsclaude-desktop.ps1)** | Claude Desktop (GUI) | Windows（未实测） | DeepSeek API（Anthropic 兼容端点） | 同上 |
| **[skills/deepseek-vision](skills/deepseek-vision/)** | skill（任何加载 SKILL.md 的 agent） | macOS / Linux | DashScope（OpenAI/Anthropic 兼容） | `qwen3.6-flash`（默认视觉模型） |
| **[dsvision-mcp](dsvision-mcp)** | MCP server（Claude Desktop / Cowork / 任何 MCP 客户端） | macOS / Linux | DashScope | `qwen3.6-flash`（默认视觉模型） |

`dsclaude` 会在 Claude Code 的 `/model` 选择器中暴露备选模型，支持会话中热切换；同时设置 `ANTHROPIC_DEFAULT_HAIKU_MODEL`，让后台/轻量任务走快模型；并支持可选的环境变量覆盖上下文窗口和输出 token 上限。

`dsclaude-desktop` 是 Claude Desktop **内置** "Configure Third-Party Inference" 功能（Developer 菜单）的一键配置工具。它把对话框需要你手填的那份 JSON 配置直接写好（已为 DeepSeek 预填）并重启 App。Anthropic 模式 ↔ Gateway 模式之间的切换由 Claude Desktop 启动选择器原生支持，所以脚本里没有 `--revert`。

## 快速开始

```bash
git clone https://github.com/Agents365-ai/dsclaude.git
cd dsclaude
```

就这样 —— 仓库里的 bash 脚本自带可执行权限，不用 `chmod`。每个工具的具体用法见下面对应小节。

如果想把 `dsclaude`（Claude Code 启动器）变成全局命令：

```bash
sudo cp dsclaude /usr/local/bin/
```

其他工具（`dsclaude-desktop`、`skills/deepseek-vision/analyze-image`）会引用自己的路径或目录，所以留在 repo 里跑就行。

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

Claude Desktop **内置**第三方推理（Third-Party Inference）功能的一键配置工具，已为 DeepSeek 预填好。

**这不是 hack 或破解。** Anthropic 在 Claude Desktop 里直接提供了 "Configure Third-Party Inference" 对话框（Developer 菜单），允许你手动把 App 指向任意 Anthropic-compatible 端点。该对话框有 6 个必填字段 + 模型列表。`dsclaude-desktop` 帮你把那个对话框会写的 JSON 配置直接写到磁盘，然后重启 App —— 省下你手点菜单填表的时间。

#### 前置条件

1. **已安装 Claude Desktop**（[claude.ai/download](https://claude.ai/download)）
2. **已启用 Developer Mode**
   - 路径：Help → Troubleshooting → Enable Developer Mode
   - 一次即可。脚本每次运行会自动校验。
3. **DeepSeek API Key** 在 `$DEEPSEEK_API_KEY` / shell rc 文件里，或运行时弹框输入

#### 用法

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # 添加到 ~/.zshrc 或 ~/.bashrc

./dsclaude-desktop      # 配置并重启 Claude Desktop
./dsclaude-desktop -h   # 帮助
```

脚本做的事：
1. 在 `~/Library/Application Support/Claude-3p/configLibrary/` 下生成一个 entry 文件，内容为：你的 DeepSeek key、base URL `https://api.deepseek.com/anthropic`、auth scheme `bearer`、模型列表 `deepseek-v4-pro` + `deepseek-v4-flash`（均启用 1M context）
2. 把 `_meta.json` 的 `appliedId` 指向这个 entry（你之前通过 GUI 配的其他 entry 不动）
3. `killall Claude && open -a Claude` 让 App 重新加载配置

#### 模式切换

Claude Desktop 启动选择器原生支持模式切换，所以脚本不需要 `--revert`：

<p align="center">
  <img src="docs/images/launch-chooser.png" alt="Claude Desktop 启动选择器：Continue with Gateway 或 Sign in to Anthropic" width="600">
</p>

即使在 Anthropic 登录页也能直接跳回 Gateway：

<p align="center">
  <img src="docs/images/sign-in-or-gateway.png" alt="登录页底部的 'Or continue with Gateway' 链接" width="600">
</p>

切换方式：在 Claude Desktop 里点头像 → Disconnect（或登出） → 下次启动时挑另一个入口。

#### 配置成功后的样子

Gateway 模式下 **Cowork** 和 **Code** 都走 DeepSeek。模型选择器里能看到你的（脱敏显示的）DeepSeek 模型：

<p align="center">
  <img src="docs/images/cowork-3p-gateway.png" alt="Cowork 模式在 Gateway 下跑 DeepSeek" width="700">
</p>

<p align="center">
  <img src="docs/images/code-3p-gateway.png" alt="Code 模式在 xxclaude 项目里跑 DeepSeek via Gateway" width="700">
</p>

> **唯一不可用的功能**：经典 **Chat**（claude.ai 风格对话）。Chat 依赖 Anthropic 托管的服务（memory / projects / artifacts / 联网搜索），这些不在 inference API 表面上，第三方 gateway 拿不到。要用 Chat 就在启动选择器选 Anthropic 模式即可。

#### Windows 版本

`dsclaude-desktop.ps1` 是 PowerShell 端口。Schema 和流程完全相同：

```powershell
$env:DEEPSEEK_API_KEY = "sk-xxxxxxxxxxxxxxxxxx"
pwsh ./dsclaude-desktop.ps1
```

前置条件与 macOS 版相同：Claude Desktop 已安装、Developer Mode 已启用、有 DeepSeek API Key。配置目录是 `%APPDATA%\Claude-3p\configLibrary\`（而非 macOS 的 `~/Library/Application Support/Claude-3p/configLibrary/`）。

> **作者未在 Windows 上实测过。** Schema 和那些坑（末尾换行、UUID 小写、Developer Mode 门控）都是 macOS 上发现的；Anthropic 在 Windows 上跑的是同一份 Electron App，理论上一致，但请在 [issue 区](https://github.com/Agents365-ai/dsclaude/issues) 反馈任何异常。

### deepseek-vision skill

给任意 agent（尤其是 DeepSeek 这种纯文本模型）补上"看图"能力的 skill。Agent 遇到图片（**本地路径或 URL 都行**）时调 `skills/deepseek-vision/analyze-image`，脚本把图发给 **Qwen3.6-Flash** （DashScope），返回文字描述写回上下文供主模型推理。

```bash
export DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxxxx

# 本地文件：
./skills/deepseek-vision/analyze-image /path/to/screenshot.png "图里报的什么错？"

# 或者 http(s) URL —— 直接传递，不下载不编码：
./skills/deepseek-vision/analyze-image https://example.com/diagram.png

# 或者 'clipboard' —— 读 macOS 剪贴板里的 PNG
# （配合 Cmd+Ctrl+Shift+4，加 Ctrl 是截图到剪贴板而不是存盘）：
./skills/deepseek-vision/analyze-image clipboard
```

任何加载 `SKILL.md` 的 agent 都能用（Claude Code / Cowork 等）。默认模型 `qwen3.6-flash`，要更准换 `DSVISION_MODEL=qwen3.6-plus`，要换厂商改 `DSVISION_BASE_URL=...`（小米 MiMo-VL via 硅基流动也是一个 base URL 的距离）。

健壮性：10MB 图片上限会提前友好报错；curl 60s 超时防挂死；空响应会检测；任何失败 stderr 出错信息 + exit 非零。

> **内联图限制**：这个 skill 需要**文件路径、URL，或 macOS 剪贴板** —— 用户**拖图、粘贴、或用 Claude Desktop "+ → Add files or photos"** 上传的图它都读不到。Cowork 把这些都做成内联 `image_url` block，不暴露文件路径给 bash skill；在 DeepSeek 这种纯文本后端会显示成 `[Unsupported Image]`。**最顺手的 workaround** 是 `clipboard` 魔术词：`Cmd+Ctrl+Shift+4` 截图到剪贴板，skill 直接读。其他情况就让用户存盘给路径或粘 URL —— **或用下面的 `dsvision-mcp`**，能彻底解决内联图问题。

### dsvision-mcp

跟 `deepseek-vision` skill 干的活一样，但能绕过 Cowork 里 skill 撞到的两个限制：

1. **沙箱网络出口管制**。Cowork VM 默认只允许出 `*.anthropic.com` / `*.claude.com`，bash skill 调 `dashscope.aliyuncs.com` 会被防火墙挡。MCP server 是 Claude Desktop 的子进程（**跑在沙箱外**），不受这个限制
2. **内联图**。Claude Code 把每张拖入/附加/粘贴的图自动缓存到 `~/.claude/image-cache/<session-uuid>/N.png`，宿主机文件系统上。MCP server 调 `analyze_image()` 不传 path 时会自动选最新一张。**拖图、+ 菜单、粘贴的场景这下都能跑通**

**安装**

```bash
pip install fastmcp requests
```

然后加到 `~/Library/Application Support/Claude-3p/claude_desktop_config.json`（如果还想给非 3P 模式用，同时加到 `Claude/` 那份）：

```json
{
  "mcpServers": {
    "dsvision": {
      "command": "/Users/<你的用户名>/path/to/dsclaude/dsvision-mcp"
    }
  }
}
```

重启 Claude Desktop。`analyze_image` 工具会自动出现在 agent 工具列表里。

**Agent 视角的用法**

```
analyze_image()                          # 自动：~/.claude/image-cache/ 里最新一张
analyze_image(image_path="/绝对/路径/foo.png")
analyze_image(focus="图里报的什么错？")    # 自定义 prompt
```

**何时用哪个**（tldr）：

| 场景 | 用哪个 |
|---|---|
| Claude Code (CLI)，给明确路径 | `skills/deepseek-vision`（零依赖，简单） |
| Cowork / Claude Desktop，内联图 | `dsvision-mcp`（**唯一能用的**） |
| Cowork 给明确路径，且不介意 patch 沙箱 | 都行 |

> 为什么是 skill 不是 MCP server：零新依赖（只用 `bash` + `curl` + `jq`）、无后台进程、单文件 2 分钟读完。

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
