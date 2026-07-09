#!/usr/bin/env node
// codex-adapter.mjs — local OpenAI Responses→Chat Completions translation proxy.
//
// Codex CLI only speaks the OpenAI Responses API, but several providers
// (DeepSeek, Kimi, Zhipu GLM, Tencent TokenHub, SiliconFlow) only expose
// Chat Completions. This adapter sits between them:
//
//   Codex --Responses--> http://127.0.0.1:8317/<provider>/v1/responses
//          --Chat------> https://<upstream>/chat/completions
//
// Zero dependencies; requires Node 18+ (global fetch). The Authorization
// header from Codex is forwarded upstream as-is, so keys stay in Codex's
// env_key mechanism and never touch this file.
//
// Usage:
//   node codex-adapter.mjs                 # listen on 127.0.0.1:8317
//   node codex-adapter.mjs --port 9000
//   CODEX_ADAPTER_PORT=9000 node codex-adapter.mjs
//
// Run in background:
//   nohup node codex-adapter.mjs > ~/.codex/adapter.log 2>&1 &
//
// Health check:
//   curl http://127.0.0.1:8317/health
//
// Notes:
// - Reasoning output (reasoning_content) is streamed back to Codex as
//   reasoning summary deltas, so thinking is visible and the stream stays
//   alive during long thinking phases.
// - `reasoning.effort` from Codex is dropped (providers differ on the
//   parameter; models default to their own thinking behavior).

import http from 'node:http';

const PORT = (() => {
  const i = process.argv.indexOf('--port');
  if (i !== -1 && process.argv[i + 1]) return Number(process.argv[i + 1]);
  return Number(process.env.CODEX_ADAPTER_PORT || 8317);
})();

const MAX_BODY_SIZE = 10 * 1024 * 1024;  // 10 MB
const UPSTREAM_TIMEOUT_MS = 10 * 60 * 1000;  // 10 minutes

// Chat-only upstreams. Override any URL with ADAPTER_<ID>_URL (uppercased id).
const UPSTREAMS = {
  deepseek:    'https://api.deepseek.com/chat/completions',
  moonshot:    'https://api.moonshot.cn/v1/chat/completions',
  zhipu:       'https://open.bigmodel.cn/api/paas/v4/chat/completions',
  tokenhub:    'https://api.lkeap.cloud.tencent.com/v1/chat/completions',
  siliconflow: 'https://api.siliconflow.cn/v1/chat/completions',
};
for (const id of Object.keys(UPSTREAMS)) {
  const env = process.env[`ADAPTER_${id.toUpperCase()}_URL`];
  if (env) UPSTREAMS[id] = env;
}

// ---- Request translation: Responses body -> Chat body ----------------------

function toChatBody(body) {
  const messages = [];
  if (body.instructions) messages.push({ role: 'system', content: body.instructions });

  const items = typeof body.input === 'string'
    ? [{ type: 'message', role: 'user', content: body.input }]
    : Array.isArray(body.input) ? body.input : [];

  for (const item of items) {
    const type = item.type || 'message';
    if (type === 'message') {
      const role = item.role === 'developer' ? 'system' : item.role;
      const content = typeof item.content === 'string'
        ? item.content
        : (item.content || []).map(p => p.text || '').join('');
      messages.push({ role, content });
    } else if (type === 'function_call') {
      const call = {
        id: item.call_id || item.id,
        type: 'function',
        function: { name: item.name, arguments: item.arguments || '' },
      };
      const last = messages[messages.length - 1];
      // Merge consecutive tool calls into one assistant turn (parallel calls).
      if (last && last.role === 'assistant' && last.tool_calls) last.tool_calls.push(call);
      else messages.push({ role: 'assistant', content: null, tool_calls: [call] });
    } else if (type === 'function_call_output') {
      const out = typeof item.output === 'string' ? item.output : JSON.stringify(item.output);
      messages.push({ role: 'tool', tool_call_id: item.call_id, content: out });
    }
    // reasoning / item_reference / other item types: nothing to send upstream.
  }

  const chat = { model: body.model, messages };

  if (Array.isArray(body.tools)) {
    const fns = body.tools.filter(t => t.type === 'function');
    if (fns.length) {
      chat.tools = fns.map(t => ({
        type: 'function',
        function: { name: t.name, description: t.description, parameters: t.parameters },
      }));
    }
  }
  if (body.tool_choice && body.tool_choice !== 'auto') chat.tool_choice = body.tool_choice;
  if (typeof body.parallel_tool_calls === 'boolean') chat.parallel_tool_calls = body.parallel_tool_calls;
  if (body.temperature != null) chat.temperature = body.temperature;
  if (body.top_p != null) chat.top_p = body.top_p;
  if (body.max_output_tokens != null) chat.max_tokens = body.max_output_tokens;
  if (body.text?.format?.type === 'json_schema') {
    chat.response_format = {
      type: 'json_schema',
      json_schema: {
        name: body.text.format.name,
        schema: body.text.format.schema,
        strict: body.text.format.strict,
      },
    };
  }
  if (body.stream) {
    chat.stream = true;
    chat.stream_options = { include_usage: true };
  }
  return chat;
}

// ---- Response translation helpers ------------------------------------------

function mapUsage(u) {
  if (!u) return null;
  return {
    input_tokens: u.prompt_tokens || 0,
    input_tokens_details: { cached_tokens: u.prompt_tokens_details?.cached_tokens || 0 },
    output_tokens: u.completion_tokens || 0,
    output_tokens_details: { reasoning_tokens: u.completion_tokens_details?.reasoning_tokens || 0 },
    total_tokens: u.total_tokens || 0,
  };
}

let respCounter = 0;

function buildOutput(msg) {
  const output = [];
  let n = 0;
  if (msg.reasoning_content) {
    output.push({
      type: 'reasoning', id: `rs_${++n}`,
      summary: [{ type: 'summary_text', text: msg.reasoning_content }], content: [],
    });
  }
  if (msg.content) {
    output.push({
      type: 'message', id: `msg_${++n}`, status: 'completed', role: 'assistant',
      content: [{ type: 'output_text', annotations: [], text: msg.content }],
    });
  }
  for (const tc of msg.tool_calls || []) {
    output.push({
      type: 'function_call', id: `fc_${++n}`, status: 'completed',
      call_id: tc.id, name: tc.function?.name, arguments: tc.function?.arguments || '',
    });
  }
  return output;
}

function toResponseObject(chatResp) {
  const choice = chatResp.choices?.[0] || {};
  const msg = choice.message || {};
  const incomplete = choice.finish_reason === 'length';
  return {
    id: `resp_${chatResp.id || ++respCounter}`,
    object: 'response',
    created_at: chatResp.created || Math.floor(Date.now() / 1000),
    status: incomplete ? 'incomplete' : 'completed',
    incomplete_details: incomplete ? { reason: 'max_output_tokens' } : null,
    error: null,
    model: chatResp.model,
    output: buildOutput(msg),
    usage: mapUsage(chatResp.usage),
  };
}

// ---- Streaming: Chat SSE -> Responses SSE -----------------------------------

// Tracks the currently-open output item and emits properly ordered
// Responses events as chat deltas arrive.
class StreamTranslator {
  constructor(write) {
    this.write = write;
    this.seq = 0;
    this.outputIndex = -1;
    this.current = null;          // 'reasoning' | 'message' | 'function_call'
    this.itemId = null;
    this.text = '';
    this.reasoning = '';
    this.calls = new Map();       // upstream tool_call index -> {itemId, callId, name, args, outputIndex}
    this.output = [];             // completed items, for response.completed
    this.usage = null;
    this.model = '';
    this.respId = `resp_${Date.now().toString(36)}${(++respCounter).toString(36)}`;
    this.created = Math.floor(Date.now() / 1000);
    this.started = false;
  }

  emit(type, extra) {
    this.write(`event: ${type}\ndata: ${JSON.stringify({ type, sequence_number: this.seq++, ...extra })}\n\n`);
  }

  snapshot(status, final = false) {
    return {
      id: this.respId, object: 'response', created_at: this.created, status,
      error: null, incomplete_details: null, model: this.model,
      output: final ? this.output : [],
      usage: final ? this.usage : null,
    };
  }

  start(model) {
    if (this.started) return;
    this.started = true;
    this.model = model || '';
    this.emit('response.created', { response: this.snapshot('in_progress') });
    this.emit('response.in_progress', { response: this.snapshot('in_progress') });
  }

  closeCurrent() {
    if (this.current === 'reasoning') {
      const item = {
        type: 'reasoning', id: this.itemId,
        summary: [{ type: 'summary_text', text: this.reasoning }], content: [],
      };
      this.emit('response.reasoning_summary_text.done', {
        item_id: this.itemId, output_index: this.outputIndex, summary_index: 0, text: this.reasoning,
      });
      this.emit('response.reasoning_summary_part.done', {
        item_id: this.itemId, output_index: this.outputIndex, summary_index: 0,
        part: { type: 'summary_text', text: this.reasoning },
      });
      this.emit('response.output_item.done', { output_index: this.outputIndex, item });
      this.output.push(item);
      this.reasoning = '';
    } else if (this.current === 'message') {
      const item = {
        type: 'message', id: this.itemId, status: 'completed', role: 'assistant',
        content: [{ type: 'output_text', annotations: [], text: this.text }],
      };
      this.emit('response.output_text.done', {
        item_id: this.itemId, output_index: this.outputIndex, content_index: 0, text: this.text,
      });
      this.emit('response.content_part.done', {
        item_id: this.itemId, output_index: this.outputIndex, content_index: 0,
        part: { type: 'output_text', annotations: [], text: this.text },
      });
      this.emit('response.output_item.done', { output_index: this.outputIndex, item });
      this.output.push(item);
      this.text = '';
    }
    this.current = null;
  }

  openItem(kind) {
    if (this.current === kind) return;
    this.closeCurrent();
    this.current = kind;
    this.outputIndex++;
    if (kind === 'reasoning') {
      this.itemId = `rs_${this.outputIndex}`;
      this.emit('response.output_item.added', {
        output_index: this.outputIndex,
        item: { type: 'reasoning', id: this.itemId, summary: [], content: [] },
      });
      this.emit('response.reasoning_summary_part.added', {
        item_id: this.itemId, output_index: this.outputIndex, summary_index: 0,
        part: { type: 'summary_text', text: '' },
      });
    } else if (kind === 'message') {
      this.itemId = `msg_${this.outputIndex}`;
      this.emit('response.output_item.added', {
        output_index: this.outputIndex,
        item: { type: 'message', id: this.itemId, status: 'in_progress', role: 'assistant', content: [] },
      });
      this.emit('response.content_part.added', {
        item_id: this.itemId, output_index: this.outputIndex, content_index: 0,
        part: { type: 'output_text', annotations: [], text: '' },
      });
    }
  }

  onChunk(chunk) {
    this.start(chunk.model);
    if (chunk.usage) this.usage = mapUsage(chunk.usage);
    const delta = chunk.choices?.[0]?.delta;
    if (!delta) return;

    if (delta.reasoning_content) {
      this.openItem('reasoning');
      this.reasoning += delta.reasoning_content;
      this.emit('response.reasoning_summary_text.delta', {
        item_id: this.itemId, output_index: this.outputIndex, summary_index: 0,
        delta: delta.reasoning_content,
      });
    }
    if (delta.content) {
      this.openItem('message');
      this.text += delta.content;
      this.emit('response.output_text.delta', {
        item_id: this.itemId, output_index: this.outputIndex, content_index: 0,
        delta: delta.content,
      });
    }
    for (const tc of delta.tool_calls || []) {
      const idx = tc.index ?? 0;
      let call = this.calls.get(idx);
      if (!call) {
        this.closeCurrent();
        this.outputIndex++;
        call = {
          itemId: `fc_${this.outputIndex}`,
          callId: tc.id || `call_${this.outputIndex}`,
          name: tc.function?.name || '',
          args: '',
          outputIndex: this.outputIndex,
        };
        this.calls.set(idx, call);
        this.emit('response.output_item.added', {
          output_index: call.outputIndex,
          item: {
            type: 'function_call', id: call.itemId, status: 'in_progress',
            call_id: call.callId, name: call.name, arguments: '',
          },
        });
      } else if (tc.function?.name) {
        call.name += tc.function.name;
      }
      // Upstream may send the real id after our placeholder was created.
      if (tc.id && tc.id !== call.callId && call.callId.startsWith('call_')) {
        call.callId = tc.id;
      }
      if (tc.function?.arguments) {
        call.args += tc.function.arguments;
        this.emit('response.function_call_arguments.delta', {
          item_id: call.itemId, output_index: call.outputIndex, delta: tc.function.arguments,
        });
      }
    }
  }

  finish(finishReason) {
    this.closeCurrent();
    for (const call of this.calls.values()) {
      const item = {
        type: 'function_call', id: call.itemId, status: 'completed',
        call_id: call.callId, name: call.name, arguments: call.args,
      };
      this.emit('response.function_call_arguments.done', {
        item_id: call.itemId, output_index: call.outputIndex, arguments: call.args,
      });
      this.emit('response.output_item.done', { output_index: call.outputIndex, item });
      this.output.push(item);
    }
    this.calls.clear();
    const status = finishReason === 'length' ? 'incomplete' : 'completed';
    const response = this.snapshot(status, true);
    if (status === 'incomplete') response.incomplete_details = { reason: 'max_output_tokens' };
    this.emit(`response.${status}`, { response });
  }

  fail(message) {
    this.start('');
    const response = this.snapshot('failed', true);
    response.error = { code: 'upstream_error', message };
    this.emit('response.failed', { response });
  }
}

// ---- HTTP server -------------------------------------------------------------

async function handleResponses(provider, body, req, res) {
  const upstream = UPSTREAMS[provider];
  const chatBody = toChatBody(body);
  const t0 = Date.now();

  const upstreamRes = await fetch(upstream, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': req.headers['authorization'] || '',
    },
    body: JSON.stringify(chatBody),
    signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
  });

  if (!upstreamRes.ok) {
    const errText = await upstreamRes.text();
    console.log(`[${provider}] ${chatBody.model} -> HTTP ${upstreamRes.status} (${Date.now() - t0}ms)`);
    res.writeHead(upstreamRes.status, { 'Content-Type': 'application/json' });
    let message = errText;
    try { message = JSON.parse(errText).error?.message || errText; } catch {}
    res.end(JSON.stringify({ error: { type: 'upstream_error', code: String(upstreamRes.status), message } }));
    return;
  }

  if (!chatBody.stream) {
    const chatResp = await upstreamRes.json();
    console.log(`[${provider}] ${chatBody.model} -> 200 non-stream (${Date.now() - t0}ms)`);
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(toResponseObject(chatResp)));
    return;
  }

  res.writeHead(200, {
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-cache',
    'Connection': 'keep-alive',
  });
  const translator = new StreamTranslator(s => res.write(s));
  let finishReason = null;
  let buffer = '';
  const decoder = new TextDecoder();

  try {
    for await (const raw of upstreamRes.body) {
      buffer += decoder.decode(raw, { stream: true });
      let nl;
      while ((nl = buffer.indexOf('\n')) !== -1) {
        const line = buffer.slice(0, nl).trim();
        buffer = buffer.slice(nl + 1);
        if (!line.startsWith('data:')) continue;
        const data = line.slice(5).trim();
        if (data === '[DONE]') continue;
        let chunk;
        try { chunk = JSON.parse(data); } catch { continue; }
        if (chunk.choices?.[0]?.finish_reason) finishReason = chunk.choices[0].finish_reason;
        translator.onChunk(chunk);
      }
    }
    translator.finish(finishReason);
    console.log(`[${provider}] ${chatBody.model} -> 200 stream done (${Date.now() - t0}ms)`);
  } catch (err) {
    translator.fail(String(err?.message || err));
    console.log(`[${provider}] ${chatBody.model} -> stream error: ${err?.message} (${Date.now() - t0}ms)`);
  }
  res.end();
}

const server = http.createServer((req, res) => {
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ ok: true, providers: Object.keys(UPSTREAMS) }));
    return;
  }

  const m = req.method === 'POST' && req.url.match(/^\/([a-z]+)\/v1\/responses$/);
  if (!m || !UPSTREAMS[m[1]]) {
    res.writeHead(404, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ error: { type: 'not_found', message: `Unknown route ${req.method} ${req.url}. Providers: ${Object.keys(UPSTREAMS).join(', ')}` } }));
    return;
  }

  const chunks = [];
  let bodySize = 0;
  req.on('data', c => {
    bodySize += c.length;
    if (bodySize > MAX_BODY_SIZE) {
      if (!res.headersSent) {
        res.writeHead(413, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { type: 'too_large', message: `Body exceeds ${MAX_BODY_SIZE / 1024 / 1024} MB limit` } }));
      }
      req.destroy();
      return;
    }
    chunks.push(c);
  });
  req.on('end', () => {
    let body;
    try { body = JSON.parse(Buffer.concat(chunks).toString('utf8')); }
    catch {
      res.writeHead(400, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: { type: 'invalid_request', message: 'Body is not valid JSON' } }));
      return;
    }
    handleResponses(m[1], body, req, res).catch(err => {
      console.error(`[${m[1]}] fatal:`, err);
      if (!res.headersSent) {
        res.writeHead(502, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { type: 'adapter_error', message: String(err?.message || err) } }));
      } else {
        res.end();
      }
    });
  });
});

server.listen(PORT, '127.0.0.1', () => {
  console.log(`codex-adapter listening on http://127.0.0.1:${PORT}`);
  console.log(`providers: ${Object.keys(UPSTREAMS).join(', ')}`);
  console.log(`route: POST /<provider>/v1/responses`);
});
