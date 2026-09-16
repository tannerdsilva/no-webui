  window.WebUIClient = (function () {
    'use strict';
    var holder = { exports: null, memory: null, wsSent: 0, eventCount: 0, config: null, transport: null };
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
        if (el) { el.innerHTML = readStr(htmlPtr, htmlLen); }
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
          if (holder.transport && typeof holder.transport.send === 'function') {
            holder.transport.send(msg);
          }
        }
      },
      storageSet: function (keyPtr, keyLen, valPtr, valLen) {
        var key = readStr(keyPtr, keyLen);
        var val = readStr(valPtr, valLen);
        try { localStorage.setItem(key, val); } catch (e) {}
      },
      storageGet: function (keyPtr, keyLen, outPtr, outLen) {
        if (!outPtr || outLen <= 0) { return 0; }
        var raw = null;
        try { raw = localStorage.getItem(readStr(keyPtr, keyLen)); } catch (e) { return 0; }
        if (!raw) { return 0; }
        var bytes = new TextEncoder().encode(raw);
        var n = Math.min(bytes.length, outLen);
        new Uint8Array(holder.memory.buffer, outPtr, n).set(bytes.subarray(0, n));
        return n;
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
  function readFrame() {
    var ptr = holder.exports.webui_frame_ptr();
    var len = holder.exports.webui_frame_len();
    return decoder(new Uint8Array(holder.memory.buffer, ptr, len));
  }
  function applyFrame() {
    var updates = JSON.parse(readFrame());
    for (var i = 0; i < updates.length; i++) {
      var u = updates[i];
      var el = document.getElementById(u.id);
      if (el) { el.outerHTML = u.html; }
    }
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
  function boot(opts) {
    return fetch(opts.wasmUrl)
      .then(function (r) { if (!r.ok) { throw new Error('wasm fetch ' + r.status); } return r.arrayBuffer(); })
      .then(function (bytes) { return WebAssembly.instantiate(bytes, wasiImports()); })
      .then(function (r) {
        holder.exports = r.instance.exports;
        holder.memory = r.instance.exports.memory;
        holder.config = readConfig();
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
          if (opts.onLoaded) { opts.onLoaded(page); }
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
        return frame;
      });
  }
  return { boot: boot, _getInstance: function () { return holder; } };
})();
