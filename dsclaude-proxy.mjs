#!/usr/bin/env node
// dsclaude-proxy.mjs — local proxy that strips metadata.user_id before
// forwarding requests to DeepSeek's Anthropic-compatible API.
//
// DeepSeek validates metadata.user_id against [a-zA-Z0-9_-]+ but Claude Code
// sends a hash that may contain base64 chars (+, /, =). This proxy rewrites
// the field to a safe value.
//
// https://github.com/Agents365-ai/dsclaude/issues/5

import { createServer } from "node:http";
import { request as httpRequest } from "node:http";
import { request as httpsRequest } from "node:https";

const PORT = parseInt(process.env.DSCLAUDE_PROXY_PORT || "19876", 10);
const UPSTREAM = new URL(
  process.env.DSCLAUDE_UPSTREAM || "https://api.deepseek.com"
);

function sanitizeUserId(raw) {
  if (typeof raw !== "string") return "dsclaude";
  const clean = raw.replace(/[^a-zA-Z0-9_-]/g, "");
  return clean.length > 0 ? clean : "dsclaude";
}

function rewriteBody(body) {
  const parsed = JSON.parse(body);
  if (parsed.metadata && typeof parsed.metadata === "object") {
    parsed.metadata.user_id = sanitizeUserId(parsed.metadata.user_id);
  }
  return JSON.stringify(parsed);
}

const server = createServer((clientReq, clientRes) => {
  const chunks = [];
  clientReq.on("data", (c) => chunks.push(c));
  clientReq.on("end", () => {
    let body = Buffer.concat(chunks);

    // Rewrite metadata.user_id for POST requests with JSON body
    if (
      clientReq.method === "POST" &&
      clientReq.headers["content-type"]?.includes("application/json")
    ) {
      try {
        body = Buffer.from(rewriteBody(body.toString()));
      } catch {
        // not valid JSON or no metadata — pass through
      }
    }

    const opts = {
      hostname: UPSTREAM.hostname,
      port: UPSTREAM.port || (UPSTREAM.protocol === "https:" ? 443 : 80),
      path: clientReq.url,
      method: clientReq.method,
      headers: {
        ...clientReq.headers,
        host: UPSTREAM.host,
        "content-length": body.length,
      },
    };

    const reqFn = UPSTREAM.protocol === "https:" ? httpsRequest : httpRequest;
    const upstreamReq = reqFn(opts, (upstreamRes) => {
      clientRes.writeHead(upstreamRes.statusCode, upstreamRes.headers);
      upstreamRes.pipe(clientRes);
    });

    upstreamReq.on("error", (err) => {
      console.error("[dsclaude-proxy] upstream error:", err.message);
      clientRes.writeHead(502);
      clientRes.end(JSON.stringify({ error: "proxy_upstream_error" }));
    });

    upstreamReq.end(body);
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`[dsclaude-proxy] listening on http://127.0.0.1:${PORT}`);
  console.log(`[dsclaude-proxy] upstream: ${UPSTREAM.origin}`);
});
