---
name: deepseek-vision
description: Use whenever the user references an image (local file path or http/https URL — screenshot, photo, diagram, UI capture, chart, error dialog) and you need to know what's in it to answer or act. Calls a vision model (Qwen3.6-Flash by default) via DashScope and returns a text description you can reason over. Especially important when running on a text-only backend like DeepSeek V4, but also useful as a dedicated OCR / detail extractor even when the main model is multimodal.
---

# Deepseek Vision Helper

When the user shares an image — file path or URL — and you need to understand its content, call this skill's `analyze-image` tool instead of trying to "see" it directly. The tool sends the image to a vision model and returns a text description.

## How to use

```bash
./skills/deepseek-vision/analyze-image <image-path-or-url> [focus prompt]
```

Accepts:
- A local file path (`/Users/me/screenshot.png`, `~/Desktop/diagram.jpg`, relative paths)
- An http/https URL — passed through directly to the API, no download needed

The script prints plaintext. Read it as if you saw the image yourself, then continue your reasoning. On error it prints to stderr and exits non-zero.

## What this skill cannot do

**Read inline images dropped, pasted, or attached into the chat.** When the user drops or pastes an image, or uses Claude Desktop's "+ → Add files or photos" attachment, the image becomes an `image_url` content block embedded in the message — there is no filesystem path the bash script can reach, and on a text-only backend it usually surfaces as `[Unsupported Image]`.

For those cases, use the **`dsvision-mcp`** server (sibling tool in this repo) instead — it runs outside Cowork's sandbox and auto-finds Claude Code's `~/.claude/image-cache/` directory.

If only this skill is available and the user shares an image inline with no path:

1. Save the image to disk and re-share with the file path, or
2. Paste an http/https URL to the image

Do not try to invent a path or guess at the image content — say what you can't see, then propose one of the two options above.

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
