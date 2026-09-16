window.WebUIClient = (function () {
  'use strict';
  var holder = { exports: null, memory: null };
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
  function wasiImports() {
    return {
      args_get: noop,
      args_sizes_get: noop,
      environ_get: noop,
      environ_sizes_get: noop,
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
    };
  }
  function readFrame() {
    var ptr = holder.exports.webui_frame_ptr();
    var len = holder.exports.webui_frame_len();
    return decoder(new Uint8Array(holder.memory.buffer, ptr, len));
  }
  function boot(opts) {
    return fetch(opts.wasmUrl)
      .then(function (r) { if (!r.ok) { throw new Error('wasm fetch ' + r.status); } return r.arrayBuffer(); })
      .then(function (bytes) { return WebAssembly.instantiate(bytes, wasiImports()); })
      .then(function (r) {
        holder.exports = r.instance.exports;
        holder.memory = r.instance.exports.memory;
        if (typeof holder.exports._start === 'function') { holder.exports._start(); }
        holder.exports.webui_render_page();
        var frame = readFrame();
        var target = document.getElementById(opts.target);
        if (target) {
          var prior = target.innerHTML;
          target.innerHTML = frame;
          target.setAttribute('data-hydration', frame === prior ? 'match' : 'mismatch');
        }
        if (opts.onLoaded) { opts.onLoaded(frame); }
        return frame;
      });
  }
  return { boot: boot, _getInstance: function () { return holder; } };
})();
