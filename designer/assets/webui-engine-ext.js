
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
      var field = el.querySelector('input');
      if (!field) { return; }
      function apply() {
        var q = String(field.value || '').toLowerCase();
        var items = el.querySelectorAll('[role=option], [role=menuitem], .command-palette__item');
        for (var i = 0; i < items.length; i++) {
          items[i].hidden = !!q && String(items[i].textContent).toLowerCase().indexOf(q) === -1;
        }
      }
      field.addEventListener('input', apply);
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
        if (e.key !== 'Enter' || e.shiftKey || el.tagName === 'TEXTAREA') { return; }
        if (el.getAttribute('data-prevent-enter') === 'false') { return; }
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
