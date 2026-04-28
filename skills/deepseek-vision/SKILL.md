---
name: deepseek-vision
description: Use when the active model can't see images natively (e.g., DeepSeek V4) and the user references an image file path you need to understand. Calls Qwen3.6-Flash with the image and returns a text description that you can reason over.
---

# Deepseek Vision Helper

The active model is text-only. When the user shares an image file path, do NOT try to see it directly — call this skill's `analyze-image` tool instead.

## How to use

```bash
./skills/deepseek-vision/analyze-image <image-path> [focus prompt]
```

The script prints plaintext. Read it as if you saw the image yourself, then continue your reasoning.

## Setup (one-time)

```bash
export DASHSCOPE_API_KEY=sk-xxxxxxxxxxxxxxxxxx   # add to ~/.zshrc
```

Get a key at https://bailian.console.aliyun.com/.

## Optional env overrides

| Variable | Default | Purpose |
|---|---|---|
| `DSVISION_MODEL` | `qwen3.6-flash` | swap to `qwen3.6-plus` for higher quality, `qwen3-vl-plus` for cheaper |
| `DSVISION_BASE_URL` | `https://dashscope.aliyuncs.com/compatible-mode/v1` | self-hosted or alternative provider |

## Example

User: "What's the error in /Users/me/screenshot.png?"

You:
```bash
./skills/deepseek-vision/analyze-image /Users/me/screenshot.png "What error message is shown?"
```

Tool output: `TypeError: cannot read property 'foo' of undefined at line 42 in app.js`

You: The screenshot shows a TypeError on line 42 — `foo` is being accessed on an undefined value. Looking at app.js:42...
