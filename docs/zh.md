---
title: dsclaude
description: 面向非 Anthropic 后端的启动器工具集
---

[English](./) · **中文** · [GitHub](https://github.com/Agents365-ai/dsclaude) · [Gitee 镜像](https://gitee.com/Agents365-ai/dsclaude)

让 [Claude Code](https://claude.ai/code) 和 Claude Desktop 接入 DeepSeek、小米 MiMo 等第三方模型后端的小工具集。

**作者：** [Agents365-ai](https://github.com/Agents365-ai) · [Bilibili](https://space.bilibili.com/441831884)

---

## 工具一览

| 工具 | 作用 | 平台 | 后端 |
|------|------|------|------|
| **[dsclaude](https://github.com/Agents365-ai/dsclaude/blob/main/dsclaude)** | Claude Code CLI 启动器 | macOS / Linux | DeepSeek |
| **[mmclaude](https://github.com/Agents365-ai/dsclaude/blob/main/mmclaude)** | Claude Code CLI 启动器 | macOS / Linux | 小米 MiMo |
| **[dsclaude-desktop](https://github.com/Agents365-ai/dsclaude/blob/main/dsclaude-desktop)** | Claude Desktop GUI 配置器 | macOS | DeepSeek |
| **[dsclaude-desktop.ps1](https://github.com/Agents365-ai/dsclaude/blob/main/dsclaude-desktop.ps1)** | Claude Desktop GUI 配置器 | Windows | DeepSeek |
| **[skills/deepseek-vision](https://github.com/Agents365-ai/dsclaude/tree/main/skills/deepseek-vision)** | 视觉识别 skill（零依赖） | macOS / Linux | DashScope Qwen |
| **[dsvision-mcp](https://github.com/Agents365-ai/dsclaude/blob/main/dsvision-mcp)** | 视觉识别 MCP 服务 | macOS / Linux | DashScope Qwen |

---

## macOS 快速开始

```bash
git clone https://github.com/Agents365-ai/dsclaude.git
cd dsclaude
chmod +x dsclaude
./dsclaude
```

---

## dsclaude — Claude Code 接入 DeepSeek

遵循 [DeepSeek Anthropic API](https://api-docs.deepseek.com/guides/anthropic_api) 指南。

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # 添加到 ~/.zshrc

dsclaude                 # 默认 deepseek-v4-pro（完整推理）
dsclaude fast            # deepseek-v4-flash（更快更便宜）
dsclaude long            # 1M 上下文窗口
dsclaude long fast       # 1M + flash
```

自动设置 DeepSeek 推荐的环境变量（`ANTHROPIC_BASE_URL`、模型映射、`CLAUDE_CODE_EFFORT_LEVEL=max`），并在 `/model` 选择器中暴露备选模型。上下文窗口上限可通过 `DSCLAUDE_MAX_TOKENS` 覆盖，effort 级别通过 `DSCLAUDE_EFFORT` 覆盖。

> 两个模型都原生支持 1M token，在 Claude Code 中需加 `[1m]` 后缀（如 `deepseek-v4-pro[1m]`），脚本已自动处理。

---

## mmclaude — Claude Code 接入小米 MiMo

```bash
export MIMO_API_KEY=sk-xxxxxxxxxxxxxxxxxx       # 按量付费
# 或
export MIMO_API_KEY=tp-xxxxxxxxxxxxxxxxxx       # Token Plan

mmclaude                  # 启动 mimo-v2.5-pro
mmclaude update           # git pull 拉取更新
```

按 key 前缀自动选择 base URL（`sk-*` → 公网，`tp-*` → Token Plan），可用 `MIMO_BASE_URL` 覆盖。所有模型槽位都指向 `mimo-v2.5-pro`，并自动 unset `ANTHROPIC_API_KEY`（避免遮蔽 bearer token）。

---

## dsclaude-desktop — Claude Desktop GUI 配置器

一键配置 Claude Desktop **内置**的 Third-Party Inference 功能（Developer 菜单），预填 DeepSeek 参数并重启 App。

### 前置条件

1. 已安装 Claude Desktop（[claude.ai/download](https://claude.ai/download)）
2. 已启用 Developer Mode（Help → Troubleshooting → Enable Developer Mode，一次即可）
3. 已设置 `DEEPSEEK_API_KEY` 环境变量

### 用法（macOS）

```bash
export DEEPSEEK_API_KEY=sk-xxxxxxxxxxxxxxxxxx
./dsclaude-desktop        # 配置并重启
./dsclaude-desktop -h     # 帮助
```

脚本在 `~/Library/Application Support/Claude-3p/configLibrary/` 下生成配置 entry，将其设为 `appliedId`，然后重启 App。原本通过 GUI 添加的其他 entry 不受影响。

### 模式切换

Claude Desktop 启动选择器原生支持 Anthropic ↔ Gateway 切换，无需 `--revert`。在 App 内点头像 → Disconnect，下次启动时选另一个入口即可。

> 唯一不可用的功能是经典 **Chat**（依赖 Anthropic 托管服务且不在 inference API 表面）。需要用 Chat 时切回 Anthropic 模式即可。

### 用法（Windows）

```powershell
$env:DEEPSEEK_API_KEY = "sk-xxxxxxxxxxxxxxxxxx"
pwsh ./dsclaude-desktop.ps1
```

**无需手动启用 Developer Mode** —— 脚本会自动创建 `developer_settings.json`。

配置目录：`%LOCALAPPDATA%\Claude-3p\configLibrary\`（若为 Store/MSIX 安装，脚本还会额外写入沙箱路径 `LocalCache\Roaming\Claude-3p\configLibrary\` 作为后备）。

已在 Windows 11 + Claude Desktop 1.7196（Windows Store, arm64）上实测通过。

---

## deepseek-vision skill — 视觉识别（零依赖方案）

给纯文本模型（如 DeepSeek）补上"看图"能力的 skill。代理遇到图片时调 `analyze-image` 脚本，发给 Qwen3.6-Flash 识别后将描述返回主模型。

```bash
export DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxxxx
./skills/deepseek-vision/analyze-image /path/to/screenshot.png "图里报的什么错？"
./skills/deepseek-vision/analyze-image https://example.com/diagram.png
```

任何加载 `SKILL.md` 的 agent（Claude Code、Cowork 等）都能用它。默认模型 `qwen3.6-flash`，可通过 `DSVISION_MODEL` 和 `DSVISION_BASE_URL` 切换。

> **限制**：需文件路径或 URL，不支持拖拽/粘贴/「+ → Add files or photos」上传的图片。这类场景请用下方的 **dsvision-mcp**。

---

## dsvision-mcp — 视觉识别（MCP 方案）

功能同上，但以 MCP 服务形式运行，绕过 Cowork 沙箱的两个限制：

1. **网络出口管制** — skill 调 DashScope API 会被沙箱防火墙拦截，MCP 服务跑在沙箱外
2. **内联图片** — 自动读取 `~/.claude/image-cache/` 中最新缓存，拖拽/粘贴/菜单上传均可正常工作（仅 macOS，Windows Cowork 不缓存内联图）

### 安装

```bash
pip3 install fastmcp requests
export DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # 建议加到 ~/.zshrc
cd /path/to/dsclaude && pwd    # 记下绝对路径
```

然后根据当前模式，在对应的配置文件中添加 MCP 服务：

| 模式 | 配置文件 |
|------|----------|
| 3P/Gateway（通过 `dsclaude-desktop` 使用 DeepSeek） | `~/Library/Application Support/Claude-3p/claude_desktop_config.json` |
| 标准 Anthropic 模式 | `~/Library/Application Support/Claude/claude_desktop_config.json` |

```json
{
  "mcpServers": {
    "dsvision": {
      "command": "/绝对/路径/dsclaude/dsvision-mcp"
    }
  }
}
```

重启 Claude Desktop 后，`analyze_image` 工具自动出现。

### 用法

```
analyze_image()                           # 自动检测最新缓存图片
analyze_image(image_path="/绝对/路径/foo.png")
analyze_image(focus="图里报的什么错？")     # 自定义 prompt
```

### 常见问题

| 现象 | 排查方向 |
|------|----------|
| 工具不显示 | 配置文件路径选错 / JSON 格式错误（用 `python3 -m json.tool` 校验） |
| 工具报错 | `DASHSCOPE_API_KEY` 未设置 |
| `ModuleNotFoundError` | 用 `pip3` 而非 `pip` |
| 找不到图片 | 传绝对路径，或检查 `~/.claude/image-cache/` 是否存在 |

### skill vs MCP 怎么选

| 场景 | 推荐 |
|------|------|
| Claude Code (CLI)，给明确路径 | `skills/deepseek-vision`（零依赖） |
| Cowork / Desktop，拖拽/粘贴内联图 | `dsvision-mcp`（唯一能用的） |
| Cowork，给明确路径，不介意沙箱限制 | 两者均可 |

---

## 社区

- **Discord：** <https://discord.gg/79JF5Atuk>
- **微信：** 扫描下方二维码

<p align="center">
  <img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/agents365ai_wechat_1.png" width="200" alt="微信交流群">
</p>

## 赞赏支持

如果这些脚本为你节省了时间，欢迎支持作者：

<table>
  <tr>
    <td align="center"><img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/wechat-pay.png" width="150" alt="微信支付"><br><b>微信支付</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/alipay.png" width="150" alt="支付宝"><br><b>支付宝</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/qrcode/buymeacoffee.png" width="150" alt="Buy Me a Coffee"><br><b>Buy Me a Coffee</b></td>
    <td align="center"><img src="https://raw.githubusercontent.com/Agents365-ai/images_payment/main/awarding/award.gif" width="150" alt="打赏"><br><b>打赏鼓励</b></td>
  </tr>
</table>

## 开源协议

[CC BY-NC 4.0](https://github.com/Agents365-ai/dsclaude/blob/main/LICENSE.md) — 非商业用途免费。**商业使用需获得授权。**
