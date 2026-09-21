(function () {
  function decoder(bytes) { return new TextDecoder().decode(bytes); }
  var exports = null;
  var memory = null;
  var mailbox = null;
  var i32 = null;
  var dv = null;

  function readStr(ptr, len) {
    if (!ptr || len <= 0) { return ""; }
    return decoder(new Uint8Array(memory.buffer, ptr, len));
  }

  function rpc(op, args) {
    var base = 64;
    var off = 0;
    dv.setInt32(base + off, op, true); off += 4;
    dv.setInt32(base + off, args.length, true); off += 4;
    for (var i = 0; i < args.length; i++) {
      var b = new TextEncoder().encode(args[i] === null ? "" : String(args[i]));
      dv.setInt32(base + off, b.length, true); off += 4;
      new Uint8Array(mailbox, base + off, b.length).set(b); off += b.length;
    }
    dv.setInt32(base + off, 0, true);
    Atomics.store(i32, 2, 1);
    postMessage({ type: "pump" });
    Atomics.notify(i32, 2);
    var spin = 0;
    while (Atomics.load(i32, 2) !== 0 && spin < 20000) { Atomics.wait(i32, 2, 1, 50); spin++; }
    var respBase = 32768;
    spin = 0;
    while (Atomics.load(i32, 3) === 0 && spin < 20000) { Atomics.wait(i32, 3, 0, 50); spin++; }
    var status = dv.getInt32(respBase, true);
    var rlen = dv.getInt32(respBase + 4, true);
    var out = rlen > 0 ? readStr(0, 0) : "";
    if (rlen > 0) { out = decoder(new Uint8Array(new Uint8Array(mailbox, respBase + 8, rlen))); }
    Atomics.store(i32, 3, 0);
    return { status: status, text: out };
  }

  function envImports() {
    return {
      memory: null,
      setInnerHTML: function (idPtr, idLen, htmlPtr, htmlLen) {
        rpc(1, [readStr(idPtr, idLen), readStr(htmlPtr, htmlLen)]);
      },
      removeElement: function (idPtr, idLen) {
        rpc(2, [readStr(idPtr, idLen)]);
      },
      getElementValue: function (idPtr, idLen, outPtr, outLen) {
        var r = rpc(3, [readStr(idPtr, idLen)]);
        if (!outPtr || outLen <= 0) { return 0; }
        var bytes = new TextEncoder().encode(r.text);
        var n = Math.min(bytes.length, outLen);
        new Uint8Array(memory.buffer, outPtr, n).set(bytes.subarray(0, n));
        return n;
      },
      setElementValue: function (idPtr, idLen, valPtr, valLen) {
        rpc(4, [readStr(idPtr, idLen), readStr(valPtr, valLen)]);
      },
      setCustomValidity: function (idPtr, idLen, msgPtr, msgLen) {
        rpc(5, [readStr(idPtr, idLen), readStr(msgPtr, msgLen)]);
      },
      wsSend: function (bytesPtr, len) {
        rpc(6, [readStr(bytesPtr, len)]);
      },
      storageGet: function (keyPtr, keyLen, outPtr, outLen) {
        var r = rpc(7, [readStr(keyPtr, keyLen)]);
        if (!outPtr || outLen <= 0) { return 0; }
        var bytes = new TextEncoder().encode(r.text);
        var n = Math.min(bytes.length, outLen);
        new Uint8Array(memory.buffer, outPtr, n).set(bytes.subarray(0, n));
        return n;
      },
      storageSet: function (keyPtr, keyLen, valPtr, valLen) {
        rpc(8, [readStr(keyPtr, keyLen), readStr(valPtr, valLen)]);
      },
      focusElement: function (idPtr, idLen) {
        rpc(9, [readStr(idPtr, idLen)]);
      },
      clipboardWrite: function (textPtr, textLen) {
        rpc(10, [readStr(textPtr, textLen)]);
      },
      broadcastSubscribe: function (channelPtr, channelLen) {
        rpc(11, [readStr(channelPtr, channelLen)]);
      },
      broadcastPublish: function (channelPtr, channelLen, dataPtr, dataLen) {
        rpc(12, [readStr(channelPtr, channelLen), readStr(dataPtr, dataLen)]);
      },
      fullscreenElement: function (idPtr, idLen) {
        rpc(13, [readStr(idPtr, idLen)]);
      },
      mediaQuery: function (queryPtr, queryLen) {
        var r = rpc(14, [readStr(queryPtr, queryLen)]);
        return r.text === "1";
      },
      now: function () { return performance.now(); },
      log: function (level, msgPtr, msgLen) {
        console.log(readStr(msgPtr, msgLen));
      }
    };
  }

  function wasiImports() {
    function setU32(ptr, value) {
      if (ptr && ptr > 0) { new DataView(memory.buffer).setUint32(ptr, value, true); }
    }
    function errno() { return 8; }
    function noop() { return 0; }
    function iovWrite(fd, iovs, iovsLen, nwritten) {
      return 8;
    }
    return {
      args_get: noop,
      args_sizes_get: function (argc, argvBufSize) { setU32(argc, 0); setU32(argvBufSize, 0); return 0; },
      environ_get: noop,
      environ_sizes_get: function (envc, envBufSize) { setU32(envc, 0); setU32(envBufSize, 0); return 0; },
      clock_res_get: noop,
      clock_time_get: function (id, prec, out) {
        var view = new DataView(memory.buffer);
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
      proc_exit: function (code) { throw new Error("wasm proc_exit " + code); },
      random_get: function (ptr, len) {
        var tmp = new Uint8Array(len);
        crypto.getRandomValues(tmp);
        new Uint8Array(memory.buffer, ptr, len).set(tmp);
        return 0;
      }
    };
  }

  function writeInput(text) {
    var bytes = new TextEncoder().encode(text);
    var ptr = exports.webui_input_ptr();
    new Uint8Array(memory.buffer, ptr, bytes.length).set(bytes);
    return { ptr: ptr, len: bytes.length };
  }

  function frameBytes() {
    var fptr = exports.webui_frame_ptr();
    var flen = exports.webui_frame_len();
    if (!fptr || flen <= 0) { return null; }
    var copy = new Uint8Array(flen);
    copy.set(new Uint8Array(memory.buffer, fptr, flen));
    return copy;
  }

  function handle(msg) {
    if (!msg || !msg.type) { return; }
    if (msg.type === "boot") {
      mailbox = msg.mailbox;
      i32 = new Int32Array(mailbox, 0, 4);
      dv = new DataView(mailbox);
      return fetch(msg.wasmUrl)
        .then(function (r) { return r.arrayBuffer(); })
        .then(function (bytes) {
          var env = envImports();
          var imports = { env: env, wasi_snapshot_preview1: wasiImports() };
          return WebAssembly.instantiate(bytes, imports);
        })
        .then(function (r) {
          exports = r.instance.exports;
          memory = r.instance.exports.memory;
          if (typeof exports._start === "function") { exports._start(); }
          var input = writeInput(JSON.stringify(msg.config || {}));
          exports.webui_init(input.ptr, input.len);
          var frame = frameBytes();
          postMessage({ type: "frame", reqId: msg.reqId, bytes: frame }, frame ? [frame.buffer] : []);
          postMessage({ type: "ready" });
        })
        .catch(function (err) { postMessage({ type: "error", message: String(err) + " :: " + String(err && err.stack || (err && err.message) || "") }); });
      }
    if (msg.type === "event") {
      var eIn = writeInput(msg.json);
      exports.webui_handle_event(eIn.ptr, eIn.len);
      var eFrame = frameBytes();
      postMessage({ type: "frame", reqId: msg.reqId, bytes: eFrame }, eFrame ? [eFrame.buffer] : []);
      return;
    }
    if (msg.type === "render_page") {
      exports.webui_render_page();
      var rFrame = frameBytes();
      postMessage({ type: "frame", reqId: msg.reqId, bytes: rFrame }, rFrame ? [rFrame.buffer] : []);
      return;
    }
    if (msg.type === "render_region") {
      var rIn = writeInput(JSON.stringify({ name: msg.name, args: msg.args || {} }));
      exports.webui_render_region(rIn.ptr, rIn.len);
      var nFrame = frameBytes();
      postMessage({ type: "frame", reqId: msg.reqId, bytes: nFrame }, nFrame ? [nFrame.buffer] : []);
      return;
    }
    if (msg.type === "apply_seq") {
      var sIn = writeInput(String(msg.seq));
      exports.webui_apply_seq(sIn.ptr, sIn.len);
      return;
    }
    if (msg.type === "state") {
      var stIn = writeInput(JSON.stringify({ path: msg.path, value: msg.value }));
      exports.webui_state_apply(stIn.ptr, stIn.len);
      postMessage({ type: "frame", reqId: msg.reqId, bytes: frameBytes() }, []);
      return;
    }
    if (msg.type === "data") {
      var dIn = writeInput(JSON.stringify({ name: msg.name, payload: msg.payload }));
      exports.webui_data_apply(dIn.ptr, dIn.len);
      postMessage({ type: "frame", reqId: msg.reqId, bytes: frameBytes() }, []);
      return;
    }
    if (msg.type === "data_bulk") {
      var memBytes = new Uint8Array(msg.bytes);
      var bp = exports.webui_data_alloc(memBytes.length);
      if (bp) {
        new Uint8Array(memory.buffer, bp, memBytes.length).set(memBytes);
        var bn = new TextEncoder().encode(msg.name);
        var bi = exports.webui_input_ptr();
        new Uint8Array(memory.buffer, bi, bn.length).set(bn);
        exports.webui_data_commit(bp, memBytes.length, bi, bn.length);
        postMessage({ type: "frame", reqId: msg.reqId, bytes: frameBytes() }, []);
      }
      return;
    }
    if (msg.type === "file") {
      var fileBytes = new Uint8Array(msg.bytes);
      var fp = exports.webui_file_alloc(fileBytes.length);
      if (fp) {
        new Uint8Array(memory.buffer, fp, fileBytes.length).set(fileBytes);
        var meta = new TextEncoder().encode(JSON.stringify({ name: msg.name, mime: msg.mime || "application/octet-stream" }));
        var fi = exports.webui_input_ptr();
        new Uint8Array(memory.buffer, fi, meta.length).set(meta);
        exports.webui_file_commit(fp, fileBytes.length, fi, meta.length);
        postMessage({ type: "frame", reqId: msg.reqId, bytes: frameBytes() }, []);
      }
      return;
    }
    if (msg.type === "broadcast_in") {
      var ch = new TextEncoder().encode(msg.channel);
      var pl = new TextEncoder().encode(msg.payload);
      var bpIn = exports.webui_input_ptr();
      new Uint8Array(memory.buffer, bpIn, ch.length).set(ch);
      new Uint8Array(memory.buffer, bpIn + ch.length, pl.length).set(pl);
      exports.webui_broadcast(bpIn, ch.length, bpIn + ch.length, pl.length);
      return;
    }
    if (msg.type === "bench") {
      if (!exports.webui_bench) { postMessage({ type: "bench_done", ms: -2 }); return; }
      var t0 = performance.now();
      exports.webui_bench(msg.n);
      var dt = performance.now() - t0;
      postMessage({ type: "bench_done", ms: dt });
      return;
    }
    if (msg.type === "demote_auth") {
      exports.webui_demote_auth();
      return;
    }
  }

  self.onmessage = function (e) {
    handle(e.data);
  };
})();
