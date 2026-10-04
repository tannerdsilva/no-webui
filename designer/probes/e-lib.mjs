// designer/probes/e-lib.mjs — shared harness for lane-E probes (engine tests).
//
// serves a self-contained page on a lane port (9260-9279): the working engine
// asset (designer/assets/webui-engine.js IS the deployed asset — WebUIAssetPlugin
// embeds it as-is), a webui-config meta pointing at a minimal ws endpoint, and a
// probe body. drives everything through Playwright from OUTSIDE the page; never
// patches the runtime under measurement. exits non-zero on failure.
//
// usage:
//   import { startProbeServer } from './e-lib.mjs'
//   const { base, wsFrames, consoleWarns, close } = await startProbeServer(port, bodyHtml, enginePath)
//   ... playwright against base ...

import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { readFileSync } from "node:fs";

const WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";

function encodeWsFrame(text) {
  const payload = Buffer.from(text, "utf8");
  const header = Buffer.alloc(2);
  header[0] = 0x81; // FIN + text frame
  header[1] = payload.length;
  return Buffer.concat([header, payload]);
}

// minimal RFC6455 server: accepts the upgrade, echoes frames unbuffered, replies
// pong to ping so the engine's ping loop never sees a timeout.
export async function startProbeServer(port, bodyHtml, { enginePath = "designer/assets/webui-engine.js", wsPath = "/ws", config = {}, routes = {} } = {}) {
  const engine = readFileSync(enginePath, "utf8");
  const extraRoutes = routes || {};

  const sockets = new Set();
  const wsCounters = new Map();

  const runtimeConfig = JSON.stringify({
    wsUrl: `ws://127.0.0.1:${port}${wsPath}`,
    logLevel: "warn",
    ...config,
  })

  const server = createServer((req, res) => {
    if (req.url === "/") {
      const html = `<!DOCTYPE html>
<html><head>
<meta name="webui-config" content='${runtimeConfig.replace(/'/g, "&#39;")}'>
<style>
  body { font: 13px ui-monospace, monospace; padding: 16px; }
  #list, #attrs, #moveset { margin: 8px 0; }
  .chip { display: inline-block; margin-right: 6px; padding: 2px 6px; border: 1px solid #999; }
  input, button { font: inherit; }
  #log { white-space: pre-wrap; color: #333; min-height: 2em; }
</style>
</head><body>
<div id="probe">
  <div id="list"></div>
  <div id="attrs"></div>
  <div id="moveset"></div>
  <div id="echo"></div>
  <div id="log"></div>
  ${bodyHtml || ""}
</div>
<script>${engine}</script>
<script>
window.__ready = function () {
  var host = document.querySelector("#probe");
  host.setAttribute("data-ready", "1");
};
document.addEventListener("DOMContentLoaded", window.__ready);
if (document.readyState !== "loading") { window.__ready(); }
</script>
</body></html>`;
      res.writeHead(200, { "Content-Type": "text/html" });
      res.end(html);
      return;
    }
    const extra = extraRoutes[req.url];
    if (extra) {
      res.writeHead(200, { "Content-Type": extra.type || "application/octet-stream" });
      res.end(extra.body);
      return;
    }
    res.writeHead(404);
    res.end("not found");
  });

  server.on("upgrade", (req, socket) => {
    const key = req.headers["sec-websocket-key"];
    if (!key) { socket.destroy(); return; }
    const accept = createHash("sha1").update(key + WS_MAGIC).digest("base64");
    socket.write(
      "HTTP/1.1 101 Switching Protocols\r\n" +
      "Upgrade: websocket\r\n" +
      "Connection: Upgrade\r\n" +
      "Sec-WebSocket-Accept: " + accept + "\r\n\r\n"
    );
    sockets.add(socket);
    wsCounters.set(socket, { sent: 0, frames: [] });
    socket.on("data", (chunk) => {
      // engine -> server frames are masked; we only need to respond to ping.
      parseClientFrames(socket, chunk);
    });
    socket.on("close", () => { sockets.delete(socket); wsCounters.delete(socket); });
    socket.on("error", () => {});
  });

  function parseClientFrames(socket, chunk) {
    // simplest handling: scan for unmasked server frames is not needed; the only
    // thing we must answer is ping (opcode 0x9). engine pings at 30s interval and
    // probes finish far sooner, so we tolerate unknown fragments silently.
    try {
      const bytes = Array.from(chunk);
      if (bytes.length < 2) return;
      const opcode = bytes[0] & 0x0f;
      let len = bytes[1] & 0x7f;
      let off = 2;
      const mask = bytes.slice(off, off + 4);
      const masked = (bytes[1] & 0x80) !== 0;
      off += masked ? 4 : 0;
      const payload = bytes.slice(off, off + len);
      if (masked) {
        for (let i = 0; i < payload.length; i++) payload[i] = payload[i] ^ mask[i % 4];
      }
      if (opcode === 0x9) {
        const pong = Buffer.alloc(2);
        pong[0] = 0x8a;
        pong[1] = 0;
        socket.write(pong);
      }
    } catch (e) {
      // never crash the probe on a partial frame.
    }
  }

  const counter = { total: 0, frames: [], elapsed: [] };
  let started = null;

  function markFrame(dir) {
    if (!started) return;
    const t = Date.now() - started;
    counter.total += 1;
    counter.frames.push({ dir, t });
    counter.elapsed.push(t);
  }

  server.sockets = sockets;
  server.wsMark = markFrame;

  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));

  const base = `http://127.0.0.1:${port}`;
  const close = () => {
    for (const s of sockets) { try { s.destroy(); } catch (e) {} }
    server.close();
  };
  return { base, engine, server, counter, close };
}
