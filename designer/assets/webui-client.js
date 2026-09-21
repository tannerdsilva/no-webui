  window.WebUIClient = (function () {
    'use strict';
    var holder = { exports: null, memory: null, wsSent: 0, eventCount: 0, config: null, transport: null, warnedNoTransport: false, worker: null, workerMode: false, mailbox: null, i32: null, frameActions: [], pendingRegion: null, onBench: null, onFrame: null, initialTarget: null };
  function decoder(bytes) { return new TextDecoder().decode(bytes); }
  function noop() { return 0; }
  function errno() { return 8; }
  function iovWrite(fd, iovs, iovsLen, nwritten) {
    var buffer = holder.memory.buffer;
    var view = new DataView(buffer);
    var out = '';
    for (var i = 0; i < iovsLen; i++) {
      var ptr = view.getUint32(iovs + i * 8, true);
      var len = view.getUint32(iovs + i * 8 + 4, true);
      out += decoder(new Uint8Array(buffer, ptr, len));
    }
    if (out.length) console.log(out);
    view.setUint32(nwritten, iovsLen ? 0 : 0, true);
    return 0;
  }
  function bridgeImports() {
    function readStr(ptr, len) {
      if (!ptr || len <= 0) { return ""; }
      return decoder(new Uint8Array(holder.memory.buffer, ptr, len));
    }
    return {
      setInnerHTML: function (idPtr, idLen, htmlPtr, htmlLen) {
        var el = document.getElementById(readStr(idPtr, idLen));
        if (el) { el.innerHTML = serializeFragment(sanitizeFragment(readStr(htmlPtr, htmlLen), el)); }
      },
      removeElement: function (idPtr, idLen) {
        var el = document.getElementById(readStr(idPtr, idLen));
        if (el) { el.remove(); }
      },
      getElementValue: function (idPtr, idLen, outPtr, outLen) {
        if (!outPtr || outLen <= 0) { return 0; }
        var el = document.getElementById(readStr(idPtr, idLen));
        var v = (el && el.value != null) ? String(el.value) : "";
        var bytes = new TextEncoder().encode(v);
        var n = Math.min(bytes.length, outLen);
        new Uint8Array(holder.memory.buffer, outPtr, n).set(bytes.subarray(0, n));
        return n;
      },
      setElementValue: function (idPtr, idLen, valPtr, valLen) {
        var el = document.getElementById(readStr(idPtr, idLen));
        if (el && el.value != null) { el.value = readStr(valPtr, valLen); }
      },
      setCustomValidity: function (idPtr, idLen, msgPtr, msgLen) {
        var el = document.getElementById(readStr(idPtr, idLen));
        if (el && typeof el.setCustomValidity === 'function') {
          el.setCustomValidity(readStr(msgPtr, msgLen));
        }
      },
      wsSend: function (bytesPtr, len) {
        var msg = readStr(bytesPtr, len);
        if (msg) {
          holder.wsSent += 1;
          if (holder.transport && holder.transport.readyState === WebSocket.OPEN) {
            holder.transport.send(msg);
          } else if (!holder.warnedNoTransport) {
            holder.warnedNoTransport = true;
            console.warn('WebUIClient wsSend dropped: no open transport');
          }
        }
      },
      storageSet: function (keyPtr, keyLen, valPtr, valLen) {
        var key = readStr(keyPtr, keyLen);
        var val = readStr(valPtr, valLen);
        if (holder.idbEnabled) {
          if (holder.idbCache) { holder.idbCache[key] = val; }
          idbPersist(key, val);
          return;
        }
        try { localStorage.setItem(key, val); } catch (e) {}
      },
      storageGet: function (keyPtr, keyLen, outPtr, outLen) {
        if (!outPtr || outLen <= 0) { return 0; }
        var raw = null;
        if (holder.idbEnabled) {
          if (holder.idbCache) {
            var cached = holder.idbCache[readStr(keyPtr, keyLen)];
            raw = (cached === undefined ? null : cached);
          }
        } else {
          try { raw = localStorage.getItem(readStr(keyPtr, keyLen)); } catch (e) { return 0; }
        }
        if (!raw) { return 0; }
        var bytes = new TextEncoder().encode(raw);
        var n = Math.min(bytes.length, outLen);
        new Uint8Array(holder.memory.buffer, outPtr, n).set(bytes.subarray(0, n));
        return n;
      },
      focusElement: function (idPtr, idLen) {
        var el = document.getElementById(readStr(idPtr, idLen));
        if (el) { el.focus(); }
      },
      clipboardWrite: function (textPtr, textLen) {
        if (!holder.config || !holder.config.capabilities || holder.config.capabilities.indexOf('clipboard') === -1) { return; }
        var text = readStr(textPtr, textLen);
        if (text && navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).catch(function () {});
        }
      },
      broadcastSubscribe: function (channelPtr, channelLen) {
        if (!holder.config || !holder.config.capabilities || holder.config.capabilities.indexOf('broadcast') === -1) { return; }
        var channel = readStr(channelPtr, channelLen);
        if (!channel) { return; }
        if (holder.broadcastChannels && holder.broadcastChannels[channel]) { return; }
        var bc = new BroadcastChannel(channel);
        bc.onmessage = function (e) {
          var payload = typeof e.data === 'string' ? e.data : JSON.stringify(e.data || {});
          var chBytes = new TextEncoder().encode(channel);
          var dBytes = new TextEncoder().encode(payload);
          var pIn = holder.exports.webui_input_ptr();
          if (chBytes.length + dBytes.length > 65536) { return; }
          new Uint8Array(holder.memory.buffer, pIn, chBytes.length).set(chBytes);
          new Uint8Array(holder.memory.buffer, pIn + chBytes.length, dBytes.length).set(dBytes);
          if (holder.exports.webui_broadcast) { holder.exports.webui_broadcast(pIn, chBytes.length, pIn + chBytes.length, dBytes.length); }
        };
        holder.broadcastChannels = holder.broadcastChannels || {};
        holder.broadcastChannels[channel] = bc;
      },
      broadcastPublish: function (channelPtr, channelLen, dataPtr, dataLen) {
        if (!holder.config || !holder.config.capabilities || holder.config.capabilities.indexOf('broadcast') === -1) { return; }
        var channel = readStr(channelPtr, channelLen);
        var data = readStr(dataPtr, dataLen);
        if (!channel) { return; }
        var bc = holder.broadcastChannels && holder.broadcastChannels[channel];
        if (bc) { bc.postMessage(data); }
      },
      fullscreenElement: function (idPtr, idLen) {
        if (!holder.config || !holder.config.capabilities || holder.config.capabilities.indexOf('fullscreen') === -1) { return; }
        var el = document.getElementById(readStr(idPtr, idLen));
        if (el && el.requestFullscreen) { el.requestFullscreen().catch(function () {}); }
      },
      mediaQuery: function (queryPtr, queryLen) {
        if (!holder.config || !holder.config.capabilities || holder.config.capabilities.indexOf('media') === -1) { return false; }
        var q = readStr(queryPtr, queryLen);
        if (!q) { return false; }
        return window.matchMedia(q).matches;
      },
      now: function () { return performance.now(); },
      log: function (level, msgPtr, msgLen) {
        var msg = readStr(msgPtr, msgLen);
        if (msg) { console.log(msg); }
      }
    };
  }
  function wasiImports() {
    function setU32(ptr, value) {
      if (ptr && ptr > 0) { new DataView(holder.memory.buffer).setUint32(ptr, value, true); }
    }
    return {
      wasi_snapshot_preview1: {
      args_get: noop,
      args_sizes_get: function (argc, argvBufSize) { setU32(argc, 0); setU32(argvBufSize, 0); return 0; },
      environ_get: noop,
      environ_sizes_get: function (envc, envBufSize) { setU32(envc, 0); setU32(envBufSize, 0); return 0; },
      clock_res_get: noop,
      clock_time_get: function (id, prec, out) {
        var view = new DataView(holder.memory.buffer);
        view.setBigUint64(out, BigInt(Date.now()) * 1000000n, true);
        return 0;
      },
      fd_close: errno,
      fd_fdstat_get: errno,
      fd_fdstat_set_flags: errno,
      fd_filestat_get: errno,
      fd_filestat_set_size: errno,
      fd_filestat_set_times: errno,
      fd_pread: errno,
      fd_prestat_get: errno,
      fd_prestat_dir_name: errno,
      fd_read: errno,
      fd_readdir: errno,
      fd_seek: errno,
      fd_sync: errno,
      fd_tell: errno,
      fd_write: iovWrite,
      path_create_directory: errno,
      path_filestat_get: errno,
      path_filestat_set_times: errno,
      path_link: errno,
      path_open: errno,
      path_readlink: errno,
      path_remove_directory: errno,
      path_rename: errno,
      path_symlink: errno,
      path_unlink_file: errno,
      poll_oneoff: errno,
      proc_exit: function (code) { throw new Error('wasm proc_exit ' + code); },
      random_get: function (ptr, len) {
        var tmp = new Uint8Array(len);
        crypto.getRandomValues(tmp);
        new Uint8Array(holder.memory.buffer, ptr, len).set(tmp);
        return 0;
      }
      },
      env: bridgeImports()
    };
  }
  var URL_ATTRS = ['href', 'src', 'action', 'formaction', 'xlink:href'];
  var UNSAFE_PROTOCOLS = /^(javascript|data|vbscript):/i;
  function stripUrlControlChars(url) {
    return String(url).replace(/[\u0000-\u0020\u007F]/g, '');
  }
  function isSafeUrl(url) {
    return !UNSAFE_PROTOCOLS.test(stripUrlControlChars(url));
  }
  function sanitizeFragment(html, el) {
    var anchor = (el && el.isConnected) ? el : document.body;
    var range = document.createRange();
    range.selectNode(anchor);
    var frag = range.createContextualFragment(html);
    var offenders = Array.prototype.slice.call(frag.querySelectorAll('*'));
    var pendingTemplates = Array.prototype.slice.call(frag.querySelectorAll('template'));
    while (pendingTemplates.length) {
      var t = pendingTemplates.shift();
      pendingTemplates = pendingTemplates.concat(Array.prototype.slice.call(t.content.querySelectorAll('template')));
      offenders = offenders.concat(Array.prototype.slice.call(t.content.querySelectorAll('*')));
    }
    for (var i = 0; i < offenders.length; i++) {
      var node = offenders[i];
      if (node.tagName === 'SCRIPT') {
        node.parentNode.removeChild(node);
        continue;
      }
      var attrs = node.attributes;
      for (var j = attrs.length - 1; j >= 0; j--) {
        var name = attrs[j].name;
        if (/^on/i.test(name)) {
          node.removeAttribute(name);
          continue;
        }
        var lower = name.toLowerCase();
        if (URL_ATTRS.indexOf(lower) !== -1 && !isSafeUrl(node.getAttribute(name))) {
          node.setAttribute(name, '');
        }
      }
    }
    return frag;
  }
  function serializeFragment(frag) {
    if (!frag.firstChild) { return ""; }
    var probe = document.createElement("div");
    probe.appendChild(frag);
    return probe.innerHTML;
  }
  function applyUpdates(updates) {
    for (var i = 0; i < updates.length; i++) {
      var u = updates[i];
      var el = document.getElementById(u.id);
      if (!el) { continue; }
      var fragment = sanitizeFragment(u.html, el);
      if (!fragment.firstChild) {
        el.remove();
        continue;
      }
      el.parentNode.replaceChild(fragment, el);
    }
  }
  function readFrame() {
    var ptr = holder.exports.webui_frame_ptr();
    var len = holder.exports.webui_frame_len();
    return decoder(new Uint8Array(holder.memory.buffer, ptr, len));
  }
  function applyFrame() {
    var updates = JSON.parse(readFrame());
    applyUpdates(updates);
  }
  function handleServerMessage(msg) {
    if (!msg || !msg.type) { return; }
    if (msg.type === 'update') {
      if (holder.workerMode && holder.worker) {
        if (typeof msg.seq === 'number') { workerSend('apply_seq', { type: 'apply_seq', seq: msg.seq }); }
        if (Array.isArray(msg.fragments)) { applyUpdates(msg.fragments); }
        return;
      }
      if (typeof msg.seq === 'number' && holder.exports && typeof holder.exports.webui_apply_seq === 'function') {
        var bytes = new TextEncoder().encode(String(msg.seq));
        var p = holder.exports.webui_input_ptr();
        new Uint8Array(holder.memory.buffer, p, bytes.length).set(bytes);
        holder.exports.webui_apply_seq(p, bytes.length);
      }
      if (Array.isArray(msg.fragments)) { applyUpdates(msg.fragments); }
      return;
    }
    if (msg.type === 'redirect') {
      if (holder.workerMode && holder.worker) { workerSend('demote_auth', { type: 'demote_auth' }); }
      if (holder.exports && typeof holder.exports.webui_demote_auth === 'function') {
        holder.exports.webui_demote_auth();
      }
      if (msg.url) {
        if (msg.replace === true) { location.replace(msg.url); } else { location.href = msg.url; }
      }
      return;
    }
    if (msg.type === 'token') {
      if (msg.token && holder.config) { holder.config.renderToken = msg.token; }
      return;
    }
    if (msg.type === 'viewspec') {
      var regionTarget = msg.id && document.getElementById(msg.id);
      if (regionTarget && msg.name) { renderRegionInto(regionTarget, msg.name, msg.args || {}); }
      return;
    }
    if (msg.type === 'state') {
      if (holder.workerMode && holder.worker) {
        sendAndApply('state', { type: 'state', path: msg.path, value: msg.value }, updatesApply);
        return;
      }
      var stBytes = new TextEncoder().encode(JSON.stringify({ path: msg.path, value: msg.value }));
      var pSt = holder.exports.webui_input_ptr();
      if (stBytes.length <= 65536 && holder.exports.webui_state_apply) {
        new Uint8Array(holder.memory.buffer, pSt, stBytes.length).set(stBytes);
        holder.exports.webui_state_apply(pSt, stBytes.length);
        if (holder.exports.webui_frame_len() > 0) { applyFrame(); }
      }
      return;
    }
    if (msg.type === 'data') {
      if (holder.workerMode && holder.worker) {
        sendAndApply('data', { type: 'data', name: msg.name, payload: msg.payload }, updatesApply);
        return;
      }
      var dtBytes = new TextEncoder().encode(JSON.stringify({ name: msg.name, payload: msg.payload }));
      var pDt = holder.exports.webui_input_ptr();
      if (dtBytes.length <= 65536 && holder.exports.webui_data_apply) {
        new Uint8Array(holder.memory.buffer, pDt, dtBytes.length).set(dtBytes);
        holder.exports.webui_data_apply(pDt, dtBytes.length);
        if (holder.exports.webui_frame_len() > 0) { applyFrame(); }
      }
      return;
    }
    if (msg.type === 'reload') { location.reload(); return; }
  }
  function openTransport() {
    if (!holder.config || !holder.config.wsUrl) { return; }
    if (holder.transport && holder.transport.readyState === WebSocket.OPEN) { return; }
    var ws;
    try { ws = new WebSocket(holder.config.wsUrl); } catch (e) { console.warn('WebUIClient ws connect failed: ' + e.message); return; }
    holder.transport = ws;
    ws.binaryType = 'arraybuffer';
    ws.onmessage = function (e) {
      if (e.data instanceof ArrayBuffer) { handleBinaryFrame(e.data); return; }
      var msg;
      try { msg = JSON.parse(e.data); } catch (err) { return; }
      handleServerMessage(msg);
    };
    ws.onclose = function () {
      if (holder.transport === ws) { holder.transport = null; }
    };
  }
  function handleBinaryFrame(buf) {
    if (!buf || buf.byteLength < 6) { return; }
    var view = new DataView(buf);
    if (view.getUint8(0) !== 0x64) { return; }
    var kind = view.getUint8(1);
    if (kind === 0x00) {
      var len = view.getUint32(2, true);
      if (6 + len > buf.byteLength) { return; }
      var text = decoder(new Uint8Array(buf, 6, len));
      var msg;
      try { msg = JSON.parse(text); } catch (err) { return; }
      handleServerMessage(msg);
      return;
    }
    if (kind === 0x01) {
      var nameLen = view.getUint32(2, true);
      var nameOff = 6;
      if (nameOff + nameLen + 4 > buf.byteLength) { return; }
      var bulkName = decoder(new Uint8Array(buf, nameOff, nameLen));
      var dataOff = nameOff + nameLen;
      var bulkLen = view.getUint32(dataOff, true);
      dataOff += 4;
      if (dataOff + bulkLen > buf.byteLength) { return; }
      if (holder.workerMode && holder.worker) {
        var bulkBytes = new Uint8Array(buf.slice(dataOff, dataOff + bulkLen)).buffer;
        sendAndApply('data_bulk', { type: 'data_bulk', name: bulkName, bytes: bulkBytes }, updatesApply, [bulkBytes]);
        return;
      }
      if (!holder.exports.webui_data_alloc || !holder.exports.webui_data_commit) { return; }
      var bulkPtr = holder.exports.webui_data_alloc(bulkLen);
      if (!bulkPtr) { return; }
      new Uint8Array(holder.memory.buffer, bulkPtr, bulkLen).set(new Uint8Array(buf, dataOff, bulkLen));
      var nameBytes = new TextEncoder().encode(bulkName);
      if (nameBytes.length > 65536) { return; }
      var nameIn = holder.exports.webui_input_ptr();
      new Uint8Array(holder.memory.buffer, nameIn, nameBytes.length).set(nameBytes);
      holder.exports.webui_data_commit(bulkPtr, bulkLen, nameIn, nameBytes.length);
      if (holder.exports.webui_frame_len() > 0) { applyFrame(); }
      return;
    }
  }

  var idbHandle = null;
  function idbOpen() {
    if (idbHandle) { return idbHandle; }
    idbHandle = new Promise(function (resolve, reject) {
      var req = indexedDB.open('webui', 1);
      req.onupgradeneeded = function () {
        var db = req.result;
        if (!db.objectStoreNames.contains('kv')) { db.createObjectStore('kv'); }
      };
      req.onsuccess = function () { resolve(req.result); };
      req.onerror = function () { reject(req.error); };
    });
    return idbHandle;
  }
  function idbHydrate() {
    return idbOpen().then(function (db) {
      return new Promise(function (resolve) {
        var tx = db.transaction('kv', 'readonly');
        var store = tx.objectStore('kv');
        var out = {};
        var cur = store.openCursor();
        cur.onsuccess = function () {
          var c = cur.result;
          if (c) { out[c.key] = c.value; c.continue(); } else { resolve(out); }
        };
        cur.onerror = function () { resolve(out); };
      });
    }).catch(function () { return {}; });
  }
  function idbPersist(key, val) {
    idbOpen().then(function (db) {
      var tx = db.transaction('kv', 'readwrite');
      tx.objectStore('kv').put(val, key);
    }).catch(function () {});
  }

  function findComponent(target) {
    var el = target;
    for (var depth = 0; el && depth < 20; depth++, el = el.parentElement) {
      if (el.getAttribute && el.getAttribute('data-component-id')) { return el; }
    }
    return null;
  }
  function readConfig() {
    var meta = document.querySelector('meta[name="webui-config"]');
    if (!meta) { return null; }
    var raw = meta.getAttribute('content');
    if (!raw) { return null; }
    try { return JSON.parse(raw); } catch (e) { return null; }
  }
  function dispatch(e, compEl, type) {
    var component = compEl.getAttribute('data-component-id');
    var event = compEl.getAttribute('data-event') || type;
    var data = {};
    if (type === 'input' || type === 'change') {
      var v = (compEl.value != null) ? compEl.value : (e.target && e.target.value);
      if (v != null) { data = { value: String(v) }; }
    }
    var env = { component: component, event: event, data: data };
    if (holder.config && holder.config.renderToken && holder.transport) {
      env.token = holder.config.renderToken;
    }
    var json = JSON.stringify(env);
    if (holder.workerMode && holder.worker) {
      holder.eventCount += 1;
      sendAndApply('event', { type: 'event', json: json }, updatesApply);
      return;
    }
    var enc = new TextEncoder().encode(json);
    var ptr = holder.exports.webui_input_ptr();
    new Uint8Array(holder.memory.buffer, ptr, enc.length).set(enc);
    holder.eventCount += 1;
    holder.exports.webui_handle_event(ptr, enc.length);
    applyFrame();
  }
  function wireEvents() {
    document.addEventListener('input', function (e) {
      var c = findComponent(e.target);
      if (c) { dispatch(e, c, 'input'); }
    });
    document.addEventListener('click', function (e) {
      var c = findComponent(e.target);
      if (c) { dispatch(e, c, 'click'); }
    });
  }
  function renderRegionInto(el, name, args) {
    if (!el || !name) { return false; }
    if (holder.workerMode && holder.worker) {
      var target = el;
      sendAndApply('render_region', { type: 'render_region', name: name, args: args || {} }, function (bytes) {
        var regionHTML = decoder(new Uint8Array(bytes));
        target.innerHTML = serializeFragment(sanitizeFragment(regionHTML, target));
        target.setAttribute('data-webui-applet-state', 'mounted');
      });
      return true;
    }
    if (!holder.exports || !holder.exports.webui_render_region) { return false; }
    var env = new TextEncoder().encode(JSON.stringify({ name: name, args: args || {} }));
    if (env.length > 65536) { return false; }
    var ptr = holder.exports.webui_input_ptr();
    new Uint8Array(holder.memory.buffer, ptr, env.length).set(env);
    var outPtr = holder.exports.webui_render_region(ptr, env.length);
    var outLen = holder.exports.webui_frame_len();
    if (!outPtr || outLen === 0) { el.setAttribute('data-webui-applet-state', 'unmapped'); return false; }
    var html = new TextDecoder().decode(new Uint8Array(holder.memory.buffer, outPtr, outLen));
    el.innerHTML = serializeFragment(sanitizeFragment(html, el));
    el.setAttribute('data-webui-applet-state', 'mounted');
    return true;
  }
  function mountApplets() {
    var regions = document.querySelectorAll('[data-webui-applet]');
    for (var i = 0; i < regions.length; i++) {
      var el = regions[i];
      var name = el.getAttribute('data-webui-applet');
      if (!name) { continue; }
      var args = {};
      try { args = JSON.parse(el.getAttribute('data-webui-args') || '{}'); } catch (e) { args = {}; }
      if (renderRegionInto(el, name, args) && holder.bootOpts && holder.bootOpts.onAppletMounted) {
        holder.bootOpts.onAppletMounted(name, el);
      }
    }
  }
  function handleRPC() {
    if (!holder.mailbox || !holder.i32) { return; }
    if (Atomics.load(holder.i32, 2) === 0) { return; }
    try {
    var dv = new DataView(holder.mailbox);
    var base = 64;
    var op = dv.getInt32(base, true);
    var argCount = dv.getInt32(base + 4, true);
    var off = 8;
    var args = [];
    for (var i = 0; i < argCount; i++) {
      var l = dv.getInt32(base + off, true); off += 4;
      args.push(decoder(new Uint8Array(new Uint8Array(holder.mailbox, base + off, l)))); off += l;
    }
    var respBase = 32768;
    var out = "";
    var status = 0;
    switch (op) {
      case 1: {
        var el = document.getElementById(args[0]);
        if (el) { el.innerHTML = serializeFragment(sanitizeFragment(args[1], el)); }
        break;
      }
      case 2: { var e2 = document.getElementById(args[0]); if (e2) { e2.remove(); } break; }
      case 3: { var e3 = document.getElementById(args[0]); out = (e3 && e3.value != null) ? String(e3.value) : ""; break; }
      case 4: { var e4 = document.getElementById(args[0]); if (e4 && e4.value != null) { e4.value = args[1]; } break; }
      case 5: { var e5 = document.getElementById(args[0]); if (e5 && typeof e5.setCustomValidity === 'function') { e5.setCustomValidity(args[1]); } break; }
      case 6: {
        if (args[0]) {
          holder.wsSent += 1;
          if (holder.transport && holder.transport.readyState === WebSocket.OPEN) { holder.transport.send(args[0]); }
        }
        break;
      }
      case 7: {
        if (holder.idbEnabled) {
          var cached = holder.idbCache ? holder.idbCache[args[0]] : null;
          out = (cached === undefined ? "" : cached);
        } else {
          try { out = localStorage.getItem(args[0]) || ""; } catch (e) { out = ""; }
        }
        break;
      }
      case 8: {
        if (holder.idbEnabled) {
          if (holder.idbCache) { holder.idbCache[args[0]] = args[1]; }
          idbPersist(args[0], args[1]);
        } else {
          try { localStorage.setItem(args[0], args[1]); } catch (e) {}
        }
        break;
      }
      case 9: { var e9 = document.getElementById(args[0]); if (e9) { e9.focus(); } break; }
      case 10: {
        if (navigator.clipboard && navigator.clipboard.writeText) { navigator.clipboard.writeText(args[0]).catch(function () {}); }
        break;
      }
      case 11: {
        var channel = args[0];
        if (!holder.broadcastChannels) { holder.broadcastChannels = {}; }
        if (!holder.broadcastChannels[channel]) {
          var bc = new BroadcastChannel(channel);
          bc.onmessage = function (e) {
            var payload = typeof e.data === 'string' ? e.data : JSON.stringify(e.data || {});
            if (holder.worker) { holder.worker.postMessage({ type: 'broadcast_in', channel: channel, payload: payload }); }
          };
          holder.broadcastChannels[channel] = bc;
        }
        break;
      }
      case 12: { var b12 = holder.broadcastChannels && holder.broadcastChannels[args[0]]; if (b12) { b12.postMessage(args[1]); } break; }
      case 13: { var e13 = document.getElementById(args[0]); if (e13 && e13.requestFullscreen) { e13.requestFullscreen().catch(function () {}); } break; }
      case 14: { try { out = window.matchMedia(args[0]).matches ? "1" : "0"; } catch (e) { out = "E"; } break; }
      default: status = 1;
    }
    var ob = new TextEncoder().encode(out);
    var n = Math.min(ob.length, 32760);
    new Uint8Array(holder.mailbox, respBase + 8, n).set(ob.subarray(0, n));
    dv.setInt32(respBase + 4, n, true);
    dv.setInt32(respBase, status, true);
    } catch (err) {
      var fdv = new DataView(holder.mailbox);
      fdv.setInt32(32768 + 4, 0, true);
      fdv.setInt32(32768, 1, true);
    }
    Atomics.store(holder.i32, 2, 0);
    Atomics.store(holder.i32, 3, 1);
    Atomics.notify(holder.i32, 3);
  }

  var frameSeq = 0;
  var frameWaiters = {};

  function sendAndApply(type, payload, applyFn, transfer) {
    if (!holder.worker) { return false; }
    frameSeq += 1;
    payload.reqId = frameSeq;
    if (applyFn) { frameWaiters[frameSeq] = applyFn; }
    holder.worker.postMessage(payload, transfer || []);
    return true;
  }

  function sendFrame(type, payload) {
    return sendAndApply(type, payload, null);
  }

  function bootWorker(opts) {
    return new Promise(function (resolve, reject) {
      var workerUrl = opts.workerUrl || '/__assets/webui-worker.js';
      var mailbox = new SharedArrayBuffer(65536);
      holder.mailbox = mailbox;
      holder.i32 = new Int32Array(mailbox, 0, 4);
      var worker = new Worker(workerUrl);
      holder.worker = worker;
      holder.workerMode = true;
      worker.onerror = function (err) {
        holder.workerError = String((err && err.message) || 'worker error');
        reject(new Error(holder.workerError));
      };
      holder.initialTarget = opts.target || 'search-app';
      frameSeq += 1;
      var bootReq = frameSeq;
      frameWaiters[bootReq] = function (bytes) {
        var target = document.getElementById(holder.initialTarget);
        if (target) { target.innerHTML = decoder(new Uint8Array(bytes)); }
        holder.bootApplied = true;
        if (holder.onBootApplied) { holder.onBootApplied(); }
      };
      worker.onmessage = function (e) {
        var msg = e.data || {};
        if (msg.type === 'pump') { handleRPC(); return; }
        if (msg.type === 'frame') {
          if (!msg.bytes) { return; }
          var waiter = frameWaiters[msg.reqId];
          if (waiter) {
            delete frameWaiters[msg.reqId];
            waiter(msg.bytes);
            return;
          }
          if (!holder.bootApplied && holder.initialTarget) {
            var fb = frameWaiters[bootReq];
            if (fb) { delete frameWaiters[bootReq]; fb(msg.bytes); }
          }
          return;
        }
        if (msg.type === 'ready') { resolve(true); return; }
        if (msg.type === 'error') { reject(new Error(msg.message)); return; }
        if (msg.type === 'bench_done') { if (holder.onBench) { holder.onBench(msg.ms); } return; }
      };
      worker.postMessage({ type: 'boot', wasmUrl: opts.wasmUrl, config: readConfig() || {}, mailbox: mailbox, reqId: bootReq });
    });
  }

  function benchInModule(n) {
    if (holder.workerMode && holder.worker) {
      return new Promise(function (resolve) {
        holder.onBench = function (ms) { holder.onBench = null; resolve(ms); };
        holder.worker.postMessage({ type: 'bench', n: n });
      });
    }
    return Promise.resolve(0);
  }

  function processDropFile(file) {
    var reader = new FileReader();
    reader.onload = function () {
      var bytes = new Uint8Array(reader.result);
      if (holder.workerMode && holder.worker) {
        var payload = bytes.slice().buffer;
        sendAndApply('file', { type: 'file', name: file.name, mime: file.type || 'application/octet-stream', bytes: payload }, updatesApply, [payload]);
        return;
      }
      if (!holder.exports.webui_file_alloc || !holder.exports.webui_file_commit) { return; }
      var ptr = holder.exports.webui_file_alloc(bytes.length);
      if (!ptr) { return; }
      new Uint8Array(holder.memory.buffer, ptr, bytes.length).set(bytes);
      var meta = new TextEncoder().encode(JSON.stringify({ name: file.name, mime: file.type || 'application/octet-stream' }));
      var pIn = holder.exports.webui_input_ptr();
      new Uint8Array(holder.memory.buffer, pIn, meta.length).set(meta);
      holder.exports.webui_file_commit(ptr, bytes.length, pIn, meta.length);
      if (holder.exports.webui_frame_len() > 0) { applyFrame(); }
    };
    reader.readAsArrayBuffer(file);
  }
  function wireFileDrops() {
    window.addEventListener('dragover', function (e) { e.preventDefault(); });
    window.addEventListener('drop', function (e) {
      e.preventDefault();
      if (e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files.length) { processDropFile(e.dataTransfer.files[0]); }
    });
  }
  function boot(opts) {
    var wantsWorker = (opts.mode === 'search' || opts.mode === 'app') && typeof SharedArrayBuffer !== 'undefined' && self.crossOriginIsolated && !opts.sync;
    if (wantsWorker) { return bootWorkerFlow(opts); }
    var bootConfig = readConfig();
    var needsIDB = bootConfig && bootConfig.persistence === 'indexeddb';
    if (needsIDB) { holder.idbEnabled = true; }
    var hydratePromise = needsIDB ? idbHydrate() : Promise.resolve({});
    return hydratePromise.then(function (cache) {
      if (needsIDB) { holder.idbCache = cache; }
      return fetch(opts.wasmUrl);
    })
      .then(function (r) { if (!r.ok) { throw new Error('wasm fetch ' + r.status); } return r.arrayBuffer(); })
      .then(function (bytes) { return WebAssembly.instantiate(bytes, wasiImports()); })
      .then(function (r) {
        holder.exports = r.instance.exports;
        holder.memory = r.instance.exports.memory;
        holder.config = bootConfig;
        holder.bootOpts = opts;
        if (typeof holder.exports._start === 'function') { holder.exports._start(); }
        var cfgPtr = 0; var cfgLen = 0;
        if (holder.config) {
          var cfgText = JSON.stringify(holder.config);
          var cfgBytes = new TextEncoder().encode(cfgText);
          cfgPtr = holder.exports.webui_input_ptr();
          new Uint8Array(holder.memory.buffer, cfgPtr, cfgBytes.length).set(cfgBytes);
          cfgLen = cfgBytes.length;
        }
        if (opts.mode === 'search') {
          holder.exports.webui_init(cfgPtr, cfgLen);
          var page = readFrame();
          var app = document.getElementById(opts.target || 'search-app');
          if (app) { app.innerHTML = page; }
          wireEvents();
          try { mountApplets(); } catch (err) { holder.mountError = String(err); }
          if (holder.config && holder.config.capabilities && holder.config.capabilities.indexOf('files') >= 0) { wireFileDrops(); }
          holder.handleServerMessage = handleServerMessage;
          holder.handleBinaryFrame = handleBinaryFrame;
          if (opts.onLoaded) { opts.onLoaded(page); }
          openTransport();
          return page;
        }
        holder.exports.webui_init(cfgPtr, cfgLen);
        holder.exports.webui_render_page();
        var frame = readFrame();
        var target = document.getElementById(opts.target);
        if (target) {
          var prior = target.innerHTML;
          target.innerHTML = frame;
          target.setAttribute('data-hydration', target.innerHTML === prior ? 'match' : 'mismatch');
        }
        if (opts.onLoaded) { opts.onLoaded(frame); }
        openTransport();
        return frame;
      });
  }
  function updatesApply(bytes) {
    var text = decoder(new Uint8Array(bytes));
    try { applyUpdates(JSON.parse(text)); } catch (e) {}
  }

  function bootWorkerFlow(opts) {
    var workerConfig = readConfig();
    holder.config = workerConfig;
    var needsIDB = workerConfig && workerConfig.persistence === 'indexeddb';
    if (needsIDB) { holder.idbEnabled = true; }
    var prep = needsIDB ? idbHydrate() : Promise.resolve({});
    return prep.then(function (cache) {
      if (needsIDB) { holder.idbCache = cache; }
      return bootWorker(opts);
    }).then(function () {
      return new Promise(function (resolve) {
        var finish = function () {
          wireEvents();
          mountApplets();
          if (holder.config && holder.config.capabilities && holder.config.capabilities.indexOf('files') >= 0) { wireFileDrops(); }
          holder.handleServerMessage = handleServerMessage;
          holder.handleBinaryFrame = handleBinaryFrame;
          holder.bench = benchInModule;
          openTransport();
          if (opts.onLoaded) { opts.onLoaded(0); }
          resolve(true);
        };
        if (holder.bootApplied) { finish(); } else { holder.onBootApplied = finish; }
      });
    });
  }

  return { boot: boot, _getInstance: function () { return holder; }, _sanitize: function (html) { var probe = document.createElement('div'); return serializeFragment(sanitizeFragment(html, probe)); } };
})();
