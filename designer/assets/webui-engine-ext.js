
window.WebUIEngineExt = (function () {
  'use strict';

  function install(register) {
    if (typeof register !== 'function') { return null; }
    var BEHAVIORS = {};
    var dragItem = null;
    var spyQueued = false;
    var timers = [];

    function num(v) {
      var t = String(v).replace(/[,\s]/g, '');
      if (!t || isNaN(Number(t))) { return null; }
      return Number(t);
    }

    function toast(text) {
      var el = document.querySelector('[data-webui-toast]');
      if (!el) {
        el = document.createElement('div');
        el.setAttribute('data-webui-toast', '');
        el.setAttribute('role', 'status');
        document.body.appendChild(el);
      }
      el.textContent = text;
      if (el.__webuiTimer) { clearTimeout(el.__webuiTimer); }
      el.__webuiTimer = setTimeout(function () {
        if (el.parentNode) { el.parentNode.removeChild(el); }
      }, 2000);
    }

    function copyText(text, done) {
      var area = document.createElement('textarea');
      area.value = text;
      area.setAttribute('readonly', '');
      area.style.position = 'fixed';
      area.style.opacity = '0';
      document.body.appendChild(area);
      try { area.select(); document.execCommand('copy'); } catch (e) { }
      document.body.removeChild(area);
      done();
    }

    function relText(ms) {
      var now = Date.now();
      var diff = now - ms;
      if (diff < 0) { diff = 0; }
      var s = Math.floor(diff / 1000);
      if (s < 60) { return '1m'; }
      if (s < 3600) { return Math.floor(s / 60) + 'm'; }
      if (s < 86400) { return Math.floor(s / 3600) + 'h'; }
      var then = new Date(ms);
      var today = new Date(now);
      var days = Math.round((new Date(today.getFullYear(), today.getMonth(), today.getDate()).getTime() -
        new Date(then.getFullYear(), then.getMonth(), then.getDate()).getTime()) / 86400000);
      if (days < 7) { return Math.max(days, 1) + 'd'; }
      var months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      var out = months[then.getMonth()] + ' ' + then.getDate();
      if (then.getFullYear() !== today.getFullYear()) { out += ', ' + String(then.getFullYear()).slice(2); }
      return out;
    }

    function paintRel(el) {
      el.textContent = relText(Number(el.getAttribute('data-reltime')));
    }

    function paintElapsed(el) {
      var s = Math.max(0, Math.floor((Date.now() - Number(el.getAttribute('data-started'))) / 1000));
      var rest = s % 60;
      el.textContent = Math.floor(s / 60) + ':' + (rest < 10 ? '0' : '') + rest;
    }

    function cellText(row, idx) {
      var cell = row.cells[idx];
      return cell ? cell.textContent.replace(/^\s+|\s+$/g, '') : '';
    }

    function sortBy(table, th) {
      var body = table.tBodies[0];
      var head = th.parentNode;
      if (!body || !head) { return; }
      var idx = 0;
      for (var i = 0; i < head.children.length; i++) { if (head.children[i] === th) { idx = i; } }
      var asc = th.getAttribute('aria-sort') !== 'ascending';
      var rows = [];
      for (var r = 0; r < body.rows.length; r++) { rows.push(body.rows[r]); }
      rows.sort(function (a, b) {
        var x = cellText(a, idx);
        var y = cellText(b, idx);
        var nx = num(x);
        var ny = num(y);
        var c = (nx !== null && ny !== null) ? nx - ny : x.localeCompare(y);
        return asc ? c : -c;
      });
      for (var j = 0; j < rows.length; j++) { body.appendChild(rows[j]); }
      for (var k = 0; k < head.children.length; k++) { head.children[k].removeAttribute('aria-sort'); }
      th.setAttribute('aria-sort', asc ? 'ascending' : 'descending');
    }

    function filterRows(table, query) {
      var body = table.tBodies[0];
      if (!body) { return; }
      var q = String(query).toLowerCase();
      for (var i = 0; i < body.rows.length; i++) {
        var row = body.rows[i];
        row.hidden = !!q && row.textContent.toLowerCase().indexOf(q) === -1;
      }
    }

    function spy() {
      var hosts = document.querySelectorAll('[data-scrollspy]');
      for (var i = 0; i < hosts.length; i++) {
        var sections = hosts[i].querySelectorAll('section[id]');
        var best = null;
        for (var j = 0; j < sections.length; j++) {
          if (sections[j].getBoundingClientRect().top <= 120) { best = sections[j]; }
          else { break; }
        }
        if (!best && sections.length) { best = sections[0]; }
        var links = document.querySelectorAll('a[href^="#"]');
        for (var k = 0; k < links.length; k++) {
          if (best && links[k].getAttribute('href') === '#' + best.id) {
            links[k].setAttribute('aria-current', 'true');
          } else if (links[k].hasAttribute('aria-current')) {
            links[k].removeAttribute('aria-current');
          }
        }
      }
    }

    function rovingKids(el) {
      var list = el.querySelectorAll('button, [href], input, select, textarea, [tabindex]');
      var out = [];
      for (var i = 0; i < list.length; i++) { if (!list[i].disabled) { out.push(list[i]); } }
      return out;
    }

    function markRoving(kids, active) {
      for (var i = 0; i < kids.length; i++) { kids[i].setAttribute('tabindex', kids[i] === active ? '0' : '-1'); }
    }

    var uploadTray = null;

    function liveEngine() {
      var api = window.WebUIEngine;
      if (!api || typeof api._getInstance !== 'function') { return null; }
      return api._getInstance();
    }

    function uploadToken() {
      var live = liveEngine();
      return live && live.config ? live.config.renderToken : null;
    }

    function sendTyped(el, name, data) {
      var id = el.getAttribute('data-component-id');
      var live = liveEngine();
      if (!id || !live || !live.wsClient || typeof live.wsClient.send !== 'function') { return; }
      var frame = { type: 'event', component: id, event: name, data: data };
      var token = uploadToken();
      if (token) { frame.token = token; }
      live.wsClient.send(frame);
    }

    function trayRoot() {
      if (uploadTray && uploadTray.parentNode) { return uploadTray; }
      uploadTray = document.querySelector('[data-webui-upload-tray]');
      if (uploadTray) { return uploadTray; }
      uploadTray = document.createElement('div');
      uploadTray.className = 'upload-tray';
      uploadTray.setAttribute('data-webui-upload-tray', '');
      uploadTray.setAttribute('role', 'status');
      uploadTray.setAttribute('aria-live', 'polite');
      document.body.appendChild(uploadTray);
      return uploadTray;
    }

    function trayRow(name) {
      var row = document.createElement('div');
      row.className = 'upload-tray__row';
      row.setAttribute('data-webui-upload-state', 'uploading');
      var label = document.createElement('span');
      label.className = 'upload-tray__name';
      label.textContent = name;
      var status = document.createElement('span');
      status.className = 'upload-tray__status';
      status.textContent = 'uploading\u2026';
      var cancel = document.createElement('button');
      cancel.type = 'button';
      cancel.className = 'upload-tray__cancel';
      cancel.textContent = 'Cancel';
      var track = document.createElement('div');
      track.className = 'upload-tray__track';
      var bar = document.createElement('div');
      bar.className = 'upload-tray__bar';
      track.appendChild(bar);
      row.appendChild(label);
      row.appendChild(status);
      row.appendChild(cancel);
      row.appendChild(track);
      trayRoot().appendChild(row);
      return { row: row, status: status, bar: bar, cancel: cancel };
    }

    function traySettle(entry, state, text, percent) {
      entry.row.setAttribute('data-webui-upload-state', state);
      entry.status.textContent = text;
      if (percent !== undefined) { entry.bar.style.width = percent + '%'; }
      if (state !== 'uploading' && entry.cancel.parentNode) {
        entry.cancel.parentNode.removeChild(entry.cancel);
      }
    }

    var uploadCounter = 0;

    function uploadName(el, name) {
      var template = el.getAttribute('data-upload-name-template');
      if (!template) { return name; }
      var dot = name.lastIndexOf('.');
      var stem = dot > 0 ? name.slice(0, dot) : name;
      var ext = dot > 0 ? name.slice(dot + 1) : '';
      var seq = null;
      var out = template.replace(/\{([a-z]+)\}/g, function (whole, token) {
        if (token === 'name') { return stem; }
        if (token === 'ext') { return ext; }
        if (token === 'ts') { return String(Date.now()); }
        if (token === 'seq') {
          if (seq === null) { uploadCounter += 1; seq = uploadCounter; }
          return String(seq);
        }
        return whole;
      });
      return out || name;
    }

    function uploadFile(el, file) {
      var route = el.getAttribute('data-upload-to') || '/upload';
      var into = el.getAttribute('data-upload-into') || '';
      var name = uploadName(el, file.name || 'file');
      var path = into ? into + '/' + name : name;
      var entry = trayRow(name);
      var xhr = new XMLHttpRequest();
      entry.cancel.addEventListener('click', function () {
        try { xhr.abort(); } catch (e) { }
      });
      xhr.open('POST', route, true);
      try { xhr.setRequestHeader('X-Upload-Name', name); } catch (e) { }
      xhr.setRequestHeader('X-Upload-Path', path);
      var token = uploadToken();
      if (token) { xhr.setRequestHeader('X-Render-Token', token); }
      xhr.upload.onprogress = function (event) {
        if (!event.lengthComputable || !event.total) { return; }
        entry.bar.style.width = Math.round((event.loaded / event.total) * 100) + '%';
      };
      xhr.onload = function () {
        var answer = null;
        try { answer = JSON.parse(xhr.responseText); } catch (e) { answer = null; }
        if (xhr.status >= 200 && xhr.status < 300 && answer && answer.ok === true) {
          var landed = String(answer.path || path);
          traySettle(entry, 'done', landed + ' \u00b7 ' + String(answer.bytes) + ' bytes', 100);
          sendTyped(el, 'upload-complete', {
            name: String(answer.name || name),
            path: landed,
            bytes: String(answer.bytes)
          });
          return;
        }
        var message = answer && answer.error ? String(answer.error) : String(xhr.responseText || '').replace(/^\s+|\s+$/g, '');
        if (!message) { message = 'HTTP ' + xhr.status; }
        traySettle(entry, 'error', message);
      };
      xhr.onerror = function () { traySettle(entry, 'error', 'network error'); };
      xhr.onabort = function () { traySettle(entry, 'cancelled', 'cancelled', 0); };
      xhr.send(file);
    }

    function uploadEntry(el, entry) {
      if (entry.isFile) {
        entry.file(function (file) { uploadFile(el, file); });
        return;
      }
      if (!entry.isDirectory || !entry.createReader) { return; }
      var reader = entry.createReader();
      var readBatch = function () {
        reader.readEntries(function (batch) {
          if (!batch || !batch.length) { return; }
          for (var i = 0; i < batch.length; i++) { uploadEntry(el, batch[i]); }
          readBatch();
        });
      };
      readBatch();
    }

    BEHAVIORS['data-upload-into'] = function (el) {
      var input = el.querySelector('input[type=file]');
      function pick() {
        if (input) { try { input.click(); } catch (e) { } }
      }
      function controlHit(target) {
        if (!target || !target.closest) { return null; }
        return target.closest('button, a, input, textarea, select, [role=button], [contenteditable], [data-no-upload-pick]');
      }
      el.addEventListener('click', function (event) {
        var hit = controlHit(event.target);
        if (hit && hit !== el) { return; }
        pick();
      });
      el.addEventListener('keydown', function (event) {
        if (event.key !== 'Enter' && event.key !== ' ') { return; }
        var hit = controlHit(event.target);
        if (hit && hit !== el) { return; }
        event.preventDefault();
        pick();
      });
      if (input) {
        input.addEventListener('change', function () {
          var files = input.files || [];
          for (var i = 0; i < files.length; i++) { uploadFile(el, files[i]); }
          input.value = '';
        });
      }
      el.addEventListener('paste', function (event) {
        var data = event.clipboardData;
        if (!data) { return; }
        var files = [];
        if (data.files && data.files.length) {
          for (var i = 0; i < data.files.length; i++) { files.push(data.files[i]); }
        } else if (data.items) {
          for (var j = 0; j < data.items.length; j++) {
            if (data.items[j].kind === 'file' && data.items[j].getAsFile) { files.push(data.items[j].getAsFile()); }
          }
        }
        var hasText = false;
        var kinds = data.types || [];
        for (var t = 0; t < kinds.length; t++) {
          if (kinds[t] === 'text/plain') { hasText = true; }
        }
        var started = 0;
        for (var k = 0; k < files.length; k++) {
          if (files[k] && String(files[k].type).indexOf('image/') === 0) { uploadFile(el, files[k]); started++; }
        }
        if (started && !hasText) { event.preventDefault(); }
      });
      el.addEventListener('dragover', function (event) { event.preventDefault(); });
      el.addEventListener('drop', function (event) {
        if (!event.dataTransfer) { return; }
        event.preventDefault();
        var items = event.dataTransfer.items;
        var entries = [];
        if (items) {
          for (var i = 0; i < items.length; i++) {
            var entry = items[i].webkitGetAsEntry ? items[i].webkitGetAsEntry() : null;
            if (entry) { entries.push(entry); }
          }
        }
        if (entries.length) {
          for (var j = 0; j < entries.length; j++) { uploadEntry(el, entries[j]); }
          return;
        }
        var files = event.dataTransfer.files || [];
        for (var k = 0; k < files.length; k++) { uploadFile(el, files[k]); }
      });
    };

    BEHAVIORS['data-reorder'] = function (el) {
      function mark() {
        for (var i = 0; i < el.children.length; i++) {
          if (el.children[i].id) { el.children[i].draggable = true; }
        }
      }
      mark();
      el.addEventListener('dragstart', function (e) {
        var item = e.target.closest ? e.target.closest('[id]') : null;
        if (item && item.parentNode === el) { dragItem = item; }
      });
      el.addEventListener('dragend', function () { dragItem = null; });
      el.addEventListener('dragover', function (e) { if (dragItem) { e.preventDefault(); } });
      el.addEventListener('drop', function (e) {
        if (!dragItem) { return; }
        e.preventDefault();
        var over = e.target.closest ? e.target.closest('[id]') : null;
        if (!over || over.parentNode !== el) { over = null; }
        if (over === dragItem) { over = null; }
        if (over) {
          var box = over.getBoundingClientRect();
          el.insertBefore(dragItem, e.clientY > box.top + box.height / 2 ? over.nextSibling : over);
        } else {
          el.appendChild(dragItem);
        }
        dragItem = null;
        mark();
        var ids = [];
        for (var i = 0; i < el.children.length; i++) { if (el.children[i].id) { ids.push(el.children[i].id); } }
        var input = document.getElementById(el.getAttribute('data-reorder') || '');
        if (input) {
          input.value = ids.join(',');
          input.dispatchEvent(new Event('change', { bubbles: true }));
        }
      });
    };

    BEHAVIORS['data-copy'] = function (el) {
      el.addEventListener('click', function () {
        var text = el.getAttribute('data-copy') || el.textContent || '';
        var done = function () { toast('Copied'); };
        if (navigator.clipboard && navigator.clipboard.writeText) {
          navigator.clipboard.writeText(text).then(done, function () { copyText(text, done); });
          return;
        }
        copyText(text, done);
      });
    };

    BEHAVIORS['data-table-enhance'] = function (el) {
      var mode = el.getAttribute('data-table-enhance') || '';
      var table = el.tagName === 'TABLE' ? el : el.querySelector('table');
      if (!table) { return; }
      if (mode.indexOf('sort') !== -1) {
        el.addEventListener('click', function (e) {
          var th = e.target.closest ? e.target.closest('th') : null;
          if (th && table.tHead && table.tHead.contains(th)) {
            sortBy(table, th);
          }
        });
      }
      if (mode.indexOf('filter') !== -1) {
        var field = el.querySelector('input[data-table-filter]');
        if (field) {
          field.addEventListener('input', function () { filterRows(table, field.value); });
        }
      }
    };

    BEHAVIORS['data-filter-list'] = function (el) {
      var source = el.getAttribute('data-filter-list') || '';
      var field = null;
      if (source) {
        try { field = document.querySelector(source); } catch (e) { field = null; }
        if (!field) { field = document.getElementById(source); }
      } else {
        field = el.querySelector('input');
      }
      if (!field) { return; }
      var panel = el.querySelector('.combo__panel');
      var target = el.getAttribute('data-filter-insert') || '';
      var template = el.getAttribute('data-filter-template');
      var clearQuery = el.hasAttribute('data-filter-clear');
      function items() {
        return el.querySelectorAll('[role=option], [role=menuitem], .command-palette__item');
      }
      function apply() {
        var q = String(field.value || '').toLowerCase();
        var list = items();
        for (var i = 0; i < list.length; i++) {
          list[i].hidden = !!q && String(list[i].textContent).toLowerCase().indexOf(q) === -1;
        }
      }
      function insert(item) {
        if (!target || template === null) { return; }
        var dest = document.getElementById(target);
        if (!dest) { return; }
        var value = String(dest.value || '');
        var ranged = typeof dest.selectionStart === 'number' && typeof dest.selectionEnd === 'number';
        var start = ranged ? dest.selectionStart : value.length;
        var head = value.slice(0, start);
        var tail = value.slice(ranged ? dest.selectionEnd : value.length);
        if (clearQuery) { head = head.replace(/\S*$/, ''); }
        var text = String(item.textContent || '').trim();
        var added = template.split('{value}').join(text);
        dest.value = head + added + tail;
        if (ranged && dest.setSelectionRange) {
          try { dest.setSelectionRange(head.length + added.length, head.length + added.length); } catch (e) { }
        }
        dest.dispatchEvent(new Event('input', { bubbles: true }));
      }
      function select(item) {
        if (!item) { return; }
        if (panel) { panel.removeAttribute('data-open'); }
        insert(item);
      }
      function itemAt(node) {
        if (!node || !node.closest) { return null; }
        var hit = node.closest('[role=option], [role=menuitem], .command-palette__item');
        return hit && el.contains(hit) ? hit : null;
      }
      field.addEventListener('input', apply);
      el.addEventListener('click', function (e) { select(itemAt(e.target)); });
      el.addEventListener('keydown', function (e) {
        if (e.key !== 'Enter') { return; }
        var hit = itemAt(document.activeElement);
        if (!hit) { return; }
        e.preventDefault();
        select(hit);
      });
      if (!panel) { return; }
      function open() {
        if (!panel.hasAttribute('data-open')) { panel.setAttribute('data-open', ''); }
      }
      field.addEventListener('focus', open);
      field.addEventListener('input', open);
      window.addEventListener('click', function (e) {
        if (panel.contains(e.target)) { return; }
        if (el.contains(e.target)) { open(); }
      });
      document.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && panel.hasAttribute('data-open')) { panel.removeAttribute('data-open'); }
      });
      document.addEventListener('click', function (e) {
        if (!panel.hasAttribute('data-open')) { return; }
        if (el.contains(e.target)) { return; }
        panel.removeAttribute('data-open');
      });
      return;
    };

    BEHAVIORS['data-drawer-toggle'] = function (el) {
      var id = el.getAttribute('data-drawer-toggle') || '';
      var root = id ? document.getElementById(id) : null;
      if (!root) { return; }
      if (!root.__webuiDrawerWatch && typeof MutationObserver === 'function') {
        root.__webuiDrawerWasOpen = root.hasAttribute('data-open');
        root.__webuiDrawerWatch = new MutationObserver(function () {
          var open = root.hasAttribute('data-open');
          if (open === root.__webuiDrawerWasOpen) { return; }
          root.__webuiDrawerWasOpen = open;
          if (open) { return; }
          var back = root.__webuiDrawerToggle;
          if (!back || !back.isConnected) { return; }
          var active = document.activeElement;
          if (active && active !== document.body && !root.contains(active)) { return; }
          try { back.focus(); } catch (e1) { }
        });
        root.__webuiDrawerWatch.observe(root, { attributes: true, attributeFilter: ['data-open'] });
      }
      function panel() { return root.querySelector('.drawer__panel'); }
      function focusPanel() {
        var box = panel();
        if (!box) { return; }
        var list = box.querySelectorAll('a[href], button, input, select, textarea, [tabindex]');
        for (var i = 0; i < list.length; i++) {
          if (list[i].disabled || list[i].getClientRects().length === 0) { continue; }
          try { list[i].focus(); } catch (e2) { }
          if (document.activeElement === list[i]) { return; }
        }
        try { box.focus(); } catch (e3) { }
      }
      el.addEventListener('click', function (e) {
        e.preventDefault();
        if (typeof window.matchMedia !== 'function' || !window.matchMedia('(max-width: 860px)').matches) { return; }
        if (root.hasAttribute('data-open')) { root.removeAttribute('data-open'); return; }
        root.__webuiDrawerToggle = el;
        root.setAttribute('data-open', '');
        focusPanel();
      });
    };

    BEHAVIORS['data-skip-to'] = function (el) {
      el.addEventListener('click', function (e) {
        var target = document.getElementById(el.getAttribute('data-skip-to') || '');
        if (!target) { return; }
        e.preventDefault();
        if (!target.hasAttribute('tabindex')) { target.setAttribute('tabindex', '-1'); }
        try { target.focus(); } catch (err) { }
        try { target.scrollIntoView({ block: 'start' }); } catch (err2) { target.scrollIntoView(); }
      });
    };

    BEHAVIORS['data-reltime'] = function (el) { paintRel(el); };

    BEHAVIORS['data-started'] = function (el) {
      el.setAttribute('data-elapsed', '');
      paintElapsed(el);
    };

    BEHAVIORS['data-inline-edit'] = function (el) {
      el.addEventListener('click', function (e) {
        var btn = e.target.closest ? e.target.closest('button, a') : null;
        if (btn) {
          if (btn.getAttribute('type') === 'button' && el.hasAttribute('data-editing')) {
            el.removeAttribute('data-editing');
          }
          return;
        }
        if (el.hasAttribute('data-editing')) { return; }
        el.setAttribute('data-editing', '');
        var field = el.querySelector('input, textarea');
        if (field && field.focus) { try { field.focus(); } catch (err) { } }
      });
      el.addEventListener('keydown', function (e) {
        if (e.key === 'Escape' && el.hasAttribute('data-editing')) { el.removeAttribute('data-editing'); }
      });
      var form = el.closest ? el.closest('form') : null;
      if (form) { form.addEventListener('submit', function () { el.removeAttribute('data-editing'); }); }
    };

    BEHAVIORS['data-roving'] = function (el) {
      var kids = rovingKids(el);
      if (!kids.length) { return; }
      var active = kids[0];
      for (var i = 0; i < kids.length; i++) { if (kids[i].getAttribute('tabindex') === '0') { active = kids[i]; } }
      markRoving(kids, active);
      el.addEventListener('keydown', function (e) {
        var at = -1;
        for (var j = 0; j < kids.length; j++) { if (kids[j] === document.activeElement) { at = j; } }
        if (at === -1) { return; }
        var step = 0;
        if (e.key === 'ArrowDown' || e.key === 'ArrowRight') { step = 1; }
        else if (e.key === 'ArrowUp' || e.key === 'ArrowLeft') { step = -1; }
        else { return; }
        e.preventDefault();
        var next = kids[(at + step + kids.length) % kids.length];
        markRoving(kids, next);
        try { next.focus(); } catch (err) { }
      });
    };

    BEHAVIORS['data-scrollspy'] = function () { spy(); };

    BEHAVIORS['data-autogrow'] = function (el) {
      if (el.tagName !== 'TEXTAREA') { return; }
      el.addEventListener('input', function () {
        el.style.height = 'auto';
        el.style.height = el.scrollHeight + 'px';
      });
      el.style.height = 'auto';
      el.style.height = el.scrollHeight + 'px';
    };

    BEHAVIORS['data-submit-on-enter'] = function (el) {
      el.addEventListener('keydown', function (e) {
        if (e.isComposing || e.keyCode === 229) { return; }
        if (e.key !== 'Enter') { return; }
        if (el.getAttribute('data-prevent-enter') === 'false') { return; }
        var mode = el.getAttribute('data-submit-on-enter') || '';
        var submit = false;
        if (mode === 'plain') { submit = !e.shiftKey; }
        else if (mode === 'meta') { submit = e.metaKey || e.ctrlKey; }
        else { submit = !e.shiftKey && el.tagName !== 'TEXTAREA'; }
        if (!submit) { return; }
        var form = el.form || (el.closest ? el.closest('form') : null);
        if (!form) { return; }
        e.preventDefault();
        if (typeof form.requestSubmit === 'function') { form.requestSubmit(); }
        else { form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true })); }
      });
    };

    BEHAVIORS['data-clear-on-submit'] = function () { };

    BEHAVIORS['data-clamp'] = function (el) {
      var parts = (el.getAttribute('data-clamp') || '').split(',');
      var min = Number(parts[0]);
      var max = Number(parts[1]);
      function clamp() {
        if (el.value === '') { return; }
        var value = Number(el.value);
        if (isNaN(value)) { return; }
        if (!isNaN(min) && value < min) { value = min; }
        if (!isNaN(max) && value > max) { value = max; }
        if (String(value) !== el.value) { el.value = String(value); }
      }
      el.addEventListener('change', clamp);
      el.addEventListener('blur', clamp);
    };

    function onDocSubmit(e) {
      var form = e.target;
      if (!form || !form.querySelectorAll) { return; }
      var list = form.querySelectorAll('[data-clear-on-submit]');
      for (var i = 0; i < list.length; i++) {
        list[i].value = '';
        list[i].checked = false;
      }
    }

    function onDocScroll() {
      if (spyQueued) { return; }
      spyQueued = true;
      setTimeout(function () { spyQueued = false; spy(); }, 100);
    }

    document.addEventListener('submit', onDocSubmit);
    document.addEventListener('scroll', onDocScroll, true);
    timers.push(setInterval(function () {
      var list = document.querySelectorAll('[data-reltime]');
      for (var i = 0; i < list.length; i++) { paintRel(list[i]); }
    }, 60000));
    timers.push(setInterval(function () {
      var list = document.querySelectorAll('[data-started]');
      for (var i = 0; i < list.length; i++) { paintElapsed(list[i]); }
    }, 1000));

    if (window.WebUIEngine && window.WebUIEngine.on && window.WebUIEngine.on.afterPatch) {
      window.WebUIEngine.on.afterPatch(function () { spy(); });
    }
    spy();

    for (var name in BEHAVIORS) {
      if (BEHAVIORS.hasOwnProperty(name)) { register(name, BEHAVIORS[name]); }
    }

    return function () {
      for (var i = 0; i < timers.length; i++) { clearInterval(timers[i]); }
      timers = [];
      document.removeEventListener('submit', onDocSubmit);
      document.removeEventListener('scroll', onDocScroll, true);
      dragItem = null;
      spyQueued = false;
    };
  }

  return { install: install };
})();
