
window.WebUIEngine = (function () {
  'use strict';

  var DEFAULTS = {
    wsUrl: null,
    wsReconnect: true,
    wsMaxReconnectDelay: 30000,
    wsPingInterval: 30000,
    wsPongTimeout: 60000,
    maxQueueSize: 1000,
    debounceInputMs: 300,
    debounceMaxWaitMs: 1000,
    optimisticSettleMs: 5000,
    logLevel: 'warn',
    renderToken: null,
    capabilities: null,
    persistence: null,
  };

  var LOG_LEVELS = { debug: 0, info: 1, warn: 2, error: 3, silent: 4 };
  var EVENT_TYPES = ['click', 'input', 'change', 'submit', 'keydown', 'keyup', 'keypress', 'focus', 'blur', 'focusin', 'focusout', 'mouseover', 'mouseout', 'mousedown', 'mouseup'];
  var LOST_ANCHOR_WARNED = {};
  var LOST_OPEN_WARNED = {};
  var RETAINED_OPEN = {};

  var afterPatchHooks = [];
  var readyHooks = [];
  var hookLog = null;

  function runHooks(hooks, arg) {
    for (var i = 0; i < hooks.length; i++) {
      try {
        hooks[i](arg);
      } catch (e) {
        if (hookLog) { hookLog.error('engine hook failed: ' + e); }
      }
    }
  }

  (function () {
    var mql = null;
    try { mql = window.matchMedia('(prefers-color-scheme: dark)'); } catch (e) { }
    var savedMode = null, savedScheme = null;
    try {
      savedMode = localStorage.getItem('webui-theme');
      savedScheme = localStorage.getItem('webui-scheme');
    } catch (e) { }
    var serverMode = document.documentElement.getAttribute('data-theme');
    var mode = (savedMode === 'light' || savedMode === 'dark' || savedMode === 'system')
      ? savedMode
      : (serverMode === 'light' || serverMode === 'dark' || serverMode === 'system') ? serverMode : 'system';
    var scheme = savedScheme || null;

    function sysDark() { return mql ? mql.matches : false; }

    function reflect() {
      var root = document.documentElement;
      root.setAttribute('data-theme', mode);
      if (scheme) {
        root.setAttribute('data-scheme', scheme);
      }
    }
    function press() {
      var modes = document.querySelectorAll('[data-theme-choice]');
      for (var i = 0; i < modes.length; i++) {
        modes[i].setAttribute('aria-pressed', modes[i].getAttribute('data-theme-choice') === mode ? 'true' : 'false');
      }
      var schemes = document.querySelectorAll('[data-scheme-choice]');
      for (var j = 0; j < schemes.length; j++) {
        schemes[j].setAttribute('aria-pressed', schemes[j].getAttribute('data-scheme-choice') === scheme ? 'true' : 'false');
      }
    }
    function announce() {
      try {
        document.dispatchEvent(new CustomEvent('webui:theme', {
          detail: { scheme: scheme, mode: mode }
        }));
      } catch (e) { }
    }
    function applyMode(next) {
      mode = next;
      try { localStorage.setItem('webui-theme', next); } catch (e) { }
      reflect();
      press();
      announce();
    }
    function applyScheme(next) {
      scheme = next;
      try { localStorage.setItem('webui-scheme', next); } catch (e) { }
      reflect();
      press();
      announce();
    }
    document.addEventListener('click', function (e) {
      var t = e.target;
      while (t && t !== document.documentElement && !(t.getAttribute &&
             (t.getAttribute('data-theme-choice') || t.getAttribute('data-scheme-choice')))) {
        t = t.parentNode;
      }
      if (!t || t === document.documentElement || !t.getAttribute) { return; }
      var nextScheme = t.getAttribute('data-scheme-choice');
      if (nextScheme) { applyScheme(nextScheme); return; }
      var next = t.getAttribute('data-theme-choice');
      if (next !== 'light' && next !== 'dark' && next !== 'system') { return; }
      applyMode(next);
    });
    if (mql && mql.addEventListener) {
      mql.addEventListener('change', function () {
        if (mode === 'system') { reflect(); announce(); }
      });
    }
    reflect();
    function pressInitial() { press(); }
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', pressInitial);
    } else {
      pressInitial();
    }
  })();

  function createLogger(level) {
    var min = LOG_LEVELS[level] || LOG_LEVELS.warn;
    return {
      debug: function (msg) { if (LOG_LEVELS.debug >= min) console.log('[WebUIEngine] ' + msg); },
      info:  function (msg) { if (LOG_LEVELS.info >= min)  console.info('[WebUIEngine] ' + msg); },
      warn:  function (msg) { if (LOG_LEVELS.warn >= min)  console.warn('[WebUIEngine] ' + msg); },
      error: function (msg) { if (LOG_LEVELS.error >= min) console.error('[WebUIEngine] ' + msg); },
    };
  }

  function createWSClient(log, onMessage) {
    var ws = null;
    var reconnectTimer = null;
    var reconnectAttempts = 0;
    var messageQueue = [];
    var isConnected = false;
    var pingTimer = null;
    var pongTimer = null;
    var config = {};
    var destroyed = false;

    function connect(url) {
      if (destroyed) return;
      if (typeof WebSocket === 'undefined') {
        log.warn('WebSocket is not available in this environment');
        return;
      }
      if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) return;

      var wsUrl = url || config.wsUrl || 'ws://' + location.host + '/ws';
      log.info('Connecting to ' + wsUrl);
      ws = new WebSocket(wsUrl);

      ws.onopen = function () {
        if (destroyed) return;
        log.info('Connected');
        isConnected = true;
        reconnectAttempts = 0;
        flushQueue();
        startPing();
        dispatchEvent('webui:connected', {});
      };

      ws.onmessage = function (e) {
        if (destroyed) return;
        try {
          var msg = JSON.parse(e.data);
          if (msg && msg.type === 'pong' && pongTimer) {
            clearTimeout(pongTimer);
            pongTimer = null;
          }
          onMessage(msg);
        } catch (err) {
          log.error('Failed to parse message: ' + err.message);
        }
      };

      ws.onclose = function () {
        if (destroyed) return;
        log.info('Disconnected');
        isConnected = false;
        stopPing();
        dispatchEvent('webui:disconnected', {});
        if (config.wsReconnect) scheduleReconnect();
      };

      ws.onerror = function () {  };
    }

    function disconnect() {
      destroyed = true;
      stopPing();
      if (reconnectTimer) { clearTimeout(reconnectTimer); reconnectTimer = null; }
      if (ws) {
        ws.onclose = null;
        ws.close();
        ws = null;
      }
      isConnected = false;
    }

    function scheduleReconnect() {
      if (reconnectTimer || destroyed) return;

      var baseDelay = Math.min(1000 * Math.pow(2, reconnectAttempts), config.wsMaxReconnectDelay);
      var jitter = 0.5 + Math.random();
      var delay = Math.round(baseDelay * jitter);
      reconnectAttempts++;
      log.info('Reconnecting in ' + delay + 'ms (attempt ' + reconnectAttempts + ')');
      reconnectTimer = setTimeout(function () {
        reconnectTimer = null;
        connect();
      }, delay);
    }

    function send(data) {
      if (destroyed) return;
      if (ws && ws.readyState === WebSocket.OPEN) {
        ws.send(JSON.stringify(data));
      } else {
        if (messageQueue.length >= config.maxQueueSize) {
          messageQueue.shift();
        }
        messageQueue.push(data);
        if (!reconnectTimer) connect();
      }
    }

    function flushQueue() {
      while (messageQueue.length > 0) {
        var item = messageQueue.shift();
        if (ws && ws.readyState === WebSocket.OPEN) {
          ws.send(JSON.stringify(item));
        } else {
          messageQueue.unshift(item);
          break;
        }
      }
    }

    function startPing() {
      stopPing();
      pingTimer = setInterval(function () {
        if (ws && ws.readyState === WebSocket.OPEN) {
          var pingMsg = { type: 'ping' };
          if (config.renderToken) pingMsg.token = config.renderToken;
          ws.send(JSON.stringify(pingMsg));

          if (pongTimer) clearTimeout(pongTimer);
          pongTimer = setTimeout(function () {
            log.warn('Pong timeout — reconnecting');
            if (ws) { ws.onclose = null; ws.close(); ws = null; }
            isConnected = false;
            scheduleReconnect();
          }, config.wsPongTimeout);
        }
      }, config.wsPingInterval);
    }

    function stopPing() {
      if (pingTimer) { clearInterval(pingTimer); pingTimer = null; }
      if (pongTimer) { clearTimeout(pongTimer); pongTimer = null; }
    }

    function reset(config_) {
      destroyed = false;
      config = config_;
      messageQueue = [];
      reconnectAttempts = 0;
    }

    return {
      connect: connect,
      disconnect: disconnect,
      send: send,
      reset: reset,
      isConnected: function () { return isConnected; },
    };
  }

  function createEventDelegator(log, send, fragmentPatcher) {
    var inputTimers = {};
    var listeners = [];
    var config = {};

    function mount() {
      EVENT_TYPES.forEach(function (eventType) {
        var listener = function (e) { handleEvent(e); };
        document.addEventListener(eventType, listener, false);
        listeners.push({ type: eventType, listener: listener });
      });
      log.debug('Event delegation mounted for: ' + EVENT_TYPES.join(', '));
    }

    function unmount() {
      listeners.forEach(function (entry) {
        document.removeEventListener(entry.type, entry.listener, false);
      });
      listeners = [];

      for (var key in inputTimers) {
        if (inputTimers.hasOwnProperty(key) && inputTimers[key].timer) {
          clearTimeout(inputTimers[key].timer);
        }
      }
      inputTimers = {};
      log.debug('Event delegation unmounted');
    }

    function echoInput(event) {
      var target = event.target;
      if (!target || !target.getAttribute) return;
      var echoId = target.getAttribute('data-webui-echo');
      if (!echoId) return;
      var value = target.value === undefined || target.value === null ? '' : String(target.value);
      if (typeof fragmentPatcher.echo === 'function') {
        fragmentPatcher.echo(echoId, value);
      }
    }

    function applyPrediction(componentEl, componentId) {
      var raw = componentEl.getAttribute('data-optimistic');
      if (!raw) return;
      var pred;
      try {
        pred = JSON.parse(raw);
      } catch (e) {
        log.warn('invalid data-optimistic json on #' + componentId);
        return;
      }
      if (!Array.isArray(pred)) {
        log.warn('data-optimistic payload is not an array on #' + componentId);
        return;
      }
      fragmentPatcher.patch(pred, null, true);
    }

    function effectiveTypes(event) {
      var types = [event.type];
      if (event.type === 'focusin') types.push('focus');
      if (event.type === 'focusout') types.push('blur');
      return types;
    }

    function handleEvent(event) {
      if (event.type === 'input') {
        echoInput(event);
      }
      if (event.type === 'keydown') {
        var treeRow = event.target && event.target.closest && event.target.closest('.tree--interactive [role=treeitem]');
        if (treeRow && (event.key === 'Enter' || event.key === ' ')) {
          event.preventDefault();
          treeRow.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
          return;
        }
      }
      if (event.type === 'keydown' && event.key === 'Enter' && !event.shiftKey) {
        var editTarget = event.target;
        if (editTarget && editTarget.tagName === 'TEXTAREA' && editTarget.closest('form.composer')) {
          event.preventDefault();
          var form = editTarget.closest('form.composer');
          if (typeof form.requestSubmit === 'function') {
            form.requestSubmit();
          } else {
            form.dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }));
          }
          return;
        }
      }

      if (event.type === 'keydown' && event.key === 'Escape') {
        var overlay = event.target && event.target.closest && event.target.closest('.modal-overlay');
        if (overlay) {
          var dismissBtn = overlay.querySelector('[data-dismiss]');
          if (dismissBtn) {
            dismissBtn.dispatchEvent(new MouseEvent('click', { bubbles: true, cancelable: true }));
          }
          restoreModalFocus();
        }
      }

      var islRegion = event.target && event.target.closest ? event.target.closest('[data-webui-island]') : null;
      if (islRegion && islRegion.getAttribute && islandRegionSubscribed(islRegion, event.type)) {
        if (event.type === 'submit' && typeof event.preventDefault === 'function') { event.preventDefault(); }
        deliverIslandEvent(islRegion, event);
        return;
      }

      var componentEl = findComponent(event);
      if (!componentEl) {
        warnUnwiredControl(event);
        return;
      }

      var componentId = componentEl.getAttribute('data-component-id');
      if (!componentId) return;

      var declaredEvent = componentEl.getAttribute('data-event');
      if (declaredEvent && effectiveTypes(event).indexOf(declaredEvent) === -1) return;

      if (event.type === 'click') {
        if (event.metaKey || event.ctrlKey || event.shiftKey) return;
        var link = event.target.closest('a');
        if (link) {

          if (link.hasAttribute('download')) return;
          if (link.getAttribute('href') && link.getAttribute('href').startsWith('#')) return;
          if (link.getAttribute('target') === '_blank') return;
          event.preventDefault();
        }
      }

      if (event.type === 'keydown' && event.key === 'Enter') {
        var editTarget = event.target && (event.target.tagName === 'TEXTAREA' || event.target.isContentEditable);
        if (!editTarget && componentEl.getAttribute('data-prevent-enter') !== 'false') {
          event.preventDefault();
        }
      }

      if (event.type === 'submit') {
        event.preventDefault();
        flushPendingInputs(
          event.target && event.target.closest ? (event.target.closest('form') || event.target) : event.target,
          componentId
        );
      }

      var eventData = extractEventData(event, componentEl);

      if (event.type === 'input') {
        debounceInput(componentId, event, eventData);
        return;
      }

      if (event.type === 'click') {
        applyPrediction(componentEl, componentId);
      }

      var eventMsg = {
        type: 'event',
        component: componentId,
        event: declaredEvent || event.type,
        data: eventData,
      };
      if (config.renderToken) eventMsg.token = config.renderToken;
      send(eventMsg);
    }


    function findComponent(event) {
      var path = [];
      if (typeof event.composedPath === 'function') {
        path = event.composedPath();
      } else {
        var el = event.target;
        while (el && el !== document) {
          path.push(el);
          el = el.parentNode;
        }
        path.push(document);
      }

      var maxDepth = 20;
      for (var i = 0; i < path.length && maxDepth > 0; i++) {
        var current = path[i];
        if (current && current.hasAttribute && current.hasAttribute('data-component-id')) {
          return current;
        }
        maxDepth--;
      }

      var target = event.target;
      if (target && target.nodeType === 1) {
        var labels = null;
        try {
          if (target.labels && target.labels.length) {
            labels = target.labels;
          }
        } catch (e) {
          labels = null;
        }
        if ((!labels || !labels.length) && target.id) {
          labels = document.querySelectorAll('label[for="' + target.id + '"]');
        }
        if (labels && labels.length) {
          for (var j = 0; j < labels.length; j++) {
            if (labels[j].hasAttribute && labels[j].hasAttribute('data-component-id')) {
              return labels[j];
            }
          }
        }
      }
      return null;
    }

    function clickTargetData(target, componentEl) {
      var data = {};
      var owner = target;
      while (owner && owner !== componentEl && owner.nodeType === 1 && !owner.id) {
        owner = owner.parentNode;
      }
      if (owner && owner !== componentEl && owner.nodeType === 1 && owner.id) data.targetId = owner.id;
      if (target && typeof target.className === 'string' && target.className) data.targetClass = target.className;
      return data;
    }

    var UNWIRED_WARNED = (typeof WeakSet !== 'undefined') ? new WeakSet() : null;
    function warnUnwiredControl(event) {
      if (event.type !== 'click') return;
      var el = event.target;
      if (!el || el.nodeType !== 1) return;
      var tag = el.tagName;
      if (tag !== 'BUTTON' && !(el.getAttribute && el.getAttribute('role') === 'button')) return;
      if (el.closest && el.closest('form[action]')) return;
      if (UNWIRED_WARNED && UNWIRED_WARNED.has(el)) return;
      if (UNWIRED_WARNED) UNWIRED_WARNED.add(el);
      log.warn('click on unwired control' + (el.id ? ' #' + el.id : ' <' + tag.toLowerCase() + '>') + ' — no data-component-id in the path, no server handler. wire it with onTap/onClick/controlAttributes.');
    }

    function extractEventData(event, componentEl) {
      var target = event.target;
      switch (event.type) {
        case 'click':
          return clickTargetData(target, componentEl);

        case 'input':
        case 'change':
          if (target.type === 'checkbox' || target.type === 'radio') {
            return { value: target.value, checked: target.checked };
          }
          return { value: target.value || '' };

        case 'submit':
          return extractFormData(target);

        case 'keydown':
        case 'keyup':
        case 'keypress':
          return {
            key: event.key,
            ctrlKey: String(event.ctrlKey),
            shiftKey: String(event.shiftKey),
            altKey: String(event.altKey),
            metaKey: String(event.metaKey),
          };

        case 'focus':
        case 'blur':
        case 'mouseover':
        case 'mouseout':
        case 'mousedown':
        case 'mouseup':
          return {};

        default:
          return {};
      }
    }

    function extractFormData(form) {
      if (!form || typeof form.elements === 'undefined') return {};
      var data = {};
      for (var i = 0; i < form.elements.length; i++) {
        var el = form.elements[i];
        if (!el.name || el.disabled) continue;
        if (el.type === 'checkbox' || el.type === 'radio') {
          if (el.checked) {
            data[el.name] = el.value;
          }
        } else if (el.type === 'select-multiple') {
          var values = [];
          for (var j = 0; j < el.options.length; j++) {
            if (el.options[j].selected) values.push(el.options[j].value);
          }
          data[el.name] = values.join(',');
        } else if (el.type === 'file') {

          continue;
        } else {
          data[el.name] = el.value;
        }
      }
      return data;
    }

    function debounceInput(componentId, event, eventData) {
      var fieldKey = event.target.name || event.target.id || '';
      var key = componentId + ':' + fieldKey;
      var now = Date.now();

      if (!inputTimers[key]) {
        inputTimers[key] = { timer: null, data: eventData, eventType: event.type, lastSent: now, el: event.target, flush: null };
      }
      var entry = inputTimers[key];
      entry.data = eventData;
      entry.eventType = event.type;
      entry.el = event.target;

      entry.flush = function () {
        if (entry.timer) {
          clearTimeout(entry.timer);
          entry.timer = null;
        }
        entry.flush = null;
        entry.lastSent = Date.now();
        send({
          type: 'event',
          component: componentId,
          event: entry.eventType,
          data: entry.data,
        });
      };

      if (now - entry.lastSent >= config.debounceMaxWaitMs) {
        entry.flush();
        return;
      }

      if (entry.timer) {
        clearTimeout(entry.timer);
      }
      entry.timer = setTimeout(entry.flush, config.debounceInputMs);
    }

    function flushPendingInputs(formEl, componentId) {
      for (var key in inputTimers) {
        var entry = inputTimers[key];
        if (!entry || !entry.timer || !entry.flush) continue;
        var sameField = formEl && entry.el && formEl.contains && formEl.contains(entry.el);
        var sameComponent = componentId && key.indexOf(componentId + ':') === 0;
        if (sameField || sameComponent) {
          entry.flush();
        }
      }
    }

    function deliverIslandEvent(region, event) {
      var name = region.getAttribute('data-webui-island');
      if (!name) return;
      var mod = islandModules[name];
      if (!mod || !mod.exports || typeof mod.exports.webui_on_event !== 'function') return;
      var payload = {
        type: effectiveTypes(event)[0] || event.type,
        key: (event.key !== undefined && event.key !== null) ? String(event.key) : undefined,
        data: extractEventData(event, region),
      };
      var bytes = new TextEncoder().encode(JSON.stringify(payload));
      if (bytes.length > 65536) {
        _islandLog('island ' + name + ' event payload too large — dropped', 'warn');
        return;
      }
      var inputPtr = mod.exports.webui_input_ptr();
      new Uint8Array(mod.memory.buffer, inputPtr, bytes.length).set(bytes);
      try {
        mod.exports.webui_on_event(inputPtr, bytes.length);
      } catch (e) {
        _islandLog('island ' + name + ' webui_on_event threw: ' + e.message, 'warn');
      }
      drainIslandOps(name, mod.exports);
    }

    function reset(config_) {
      config = config_;
    }

    return { mount: mount, unmount: unmount, reset: reset };
  }

  function createFragmentPatcher(log) {
    var lastSeq = -1;
    var pending = {};
    var settleMs = 5000;
    var transitionInFlight = false;
    var callbackPending = false;
    var queued = [];
    var warnedOnce = {};
    var onReplace = null;

    function warnOnce(key, message) {
      if (warnedOnce[key]) return;
      warnedOnce[key] = true;
      log.warn(message);
    }


    function patch(fragments, seq, optimistic) {
      if (!fragments || !fragments.length) return;

      if (seq !== undefined && seq !== null) {
        if (seq <= lastSeq) {
          log.warn('Dropping duplicate/out-of-order update seq=' + seq + ' (last=' + lastSeq + ')');
          return;
        }
        lastSeq = seq;
      }

      log.debug('Patching ' + fragments.length + ' fragment(s)' + (seq !== undefined ? ' seq=' + seq : ''));

      if (optimistic) {
        applyFragments(fragments, true);
        return;
      }
      enqueue(fragments);
    }

    function enqueue(fragments) {
      for (var i = 0; i < fragments.length; i++) {
        var f = fragments[i];
        var op = (f.op === undefined || f.op === null) ? 'replace' : String(f.op);
        var coalesced = false;
        if (op !== 'append' && op !== 'remove') {
          for (var j = queued.length - 1; j >= 0; j--) {
            var queuedOp = (queued[j].op === undefined || queued[j].op === null) ? 'replace' : String(queued[j].op);
            if (queued[j].id === f.id && queuedOp !== 'remove') {
              queued[j] = f;
              coalesced = true;
              break;
            }
          }
        }
        if (!coalesced) { queued.push(f); }
      }
      flush(false);
    }

    function flush(waited) {
      if (!queued.length) return;
      if (callbackPending) return;
      var batch = queued;
      queued = [];
      if (!waited && !transitionInFlight && wantsTransition(batch)) {
        runTransition(batch);
        return;
      }
      applyFragments(batch, false);
    }

    function wantsTransition(fragments) {
      if (typeof document.startViewTransition !== 'function') return false;
      var mm = (typeof window.matchMedia === 'function') ? window.matchMedia : null;
      if (mm && mm('(prefers-reduced-motion: reduce)').matches) return false;
      for (var i = 0; i < fragments.length; i++) {
        var f = fragments[i];
        if (f && (f.op === 'append' || f.op === 'text' || f.op === 'remove' || f.op === 'attr' || f.op === 'move')) return false;
        if (f && f.transition === false) return false;
        var el = f && f.id ? document.getElementById(f.id) : null;
        if (el && el.closest && el.closest('[data-webui-transition="off"]')) return false;
      }
      return true;
    }

    function runTransition(fragments) {
      transitionInFlight = true;
      callbackPending = true;
      var started = false;
      var done = function () { transitionInFlight = false; callbackPending = false; flush(true); };
      try {
        var vt = document.startViewTransition(function () {
          applyFragments(fragments, false);
          callbackPending = false;
          flush(true);
        });
        started = true;
        var fin = vt && vt.finished;
        if (fin && typeof fin.then === 'function') {
          fin.then(done, done);
        } else {
          transitionInFlight = false;
          callbackPending = false;
        }
      } catch (e) {
        started = false;
      }
      if (!started) {
        transitionInFlight = false;
        callbackPending = false;
        applyFragments(fragments, false);
        flush(true);
      }
    }

    function applyFragments(fragments, optimistic) {
      var changed = [];
      for (var i = 0; i < fragments.length; i++) {
        var f = fragments[i];
        var op = (f.op === undefined || f.op === null) ? 'replace' : String(f.op);
        if (!f.id) {
          if (optimistic) continue;
          log.warn('Invalid fragment at index ' + i);
          continue;
        }
        if (op === 'replace' || op === 'append') {
          if (f.html === undefined) {
            if (optimistic) continue;
            log.warn('Invalid fragment at index ' + i);
            continue;
          }
        }
        if (op !== 'replace' && op !== 'append' && op !== 'text' && op !== 'remove' && op !== 'attr' && op !== 'move') {
          warnOnce('op:' + op, 'Unknown fragment op "' + op + '" for #' + f.id + ' — skipped');
          continue;
        }
        if (optimistic) {
          if (op !== 'replace' && op !== 'append') {
            warnOnce('opt:' + op, 'Fragment op "' + op + '" for #' + f.id + ' is not allowed in optimistic patches — skipped');
            continue;
          }
          if (op === 'replace') { armPending(f.id); }
        } else {
          clearPending(f.id);
        }
        if (op === 'text') {
          setTextContent(f.id, f.text === undefined || f.text === null ? '' : String(f.text));
          clearEcho(f.id);
          var textNode = document.getElementById(f.id);
          if (textNode) { changed.push(textNode); }
          continue;
        }
        if (op === 'append') {
          var added = appendChildFragment(f.id, f.html, f.before);
          if (added) { changed.push(added); }
          continue;
        }
        if (op === 'remove') {
          var removed = removeFragmentElement(f.id);
          if (removed) { changed.push(removed); }
          continue;
        }
        if (op === 'attr') {
          var attrNode = applyAttrFragment(f);
          if (attrNode) { changed.push(attrNode); }
          continue;
        }
        if (op === 'move') {
          var moved = moveFragmentElement(f);
          if (moved) { changed.push(moved); }
          continue;
        }
        replaceElement(f.id, f.html);
        clearEcho(f.id);
        var node = document.getElementById(f.id);
        if (node) { changed.push(node); }
      }
      if (changed.length) { runHooks(afterPatchHooks, changed); }
    }

    var echoOverlay = {};
    function echo(id, value) {
      var el = document.getElementById(id);
      if (!el) return false;
      echoOverlay[id] = true;
      setTextContent(id, value);
      return true;
    }
    function clearEcho(id) {
      delete echoOverlay[id];
    }

    function setTextContent(id, value) {
      var el = document.getElementById(id);
      if (!el) { log.warn('Element not found: #' + id); return; }
      if (el.textContent === value) { return; }
      if (el.childNodes.length === 1 && el.firstChild.nodeType === 3) {
        el.firstChild.data = value;
        return;
      }
      el.textContent = value;
    }

    function appendChildFragment(id, html, before) {
      var container = document.getElementById(id);
      if (!container) { log.warn('Element not found: #' + id); return null; }
      var fragment = sanitizeFragment(html, container);
      var first = fragment.firstChild;
      if (!first) { return null; }
      if (first.nodeType === 1 && first.id && document.getElementById(first.id)) {
        return null;
      }
      var anchor = null;
      if (before) {
        anchor = document.getElementById(before);
        if (anchor && !container.contains(anchor)) { anchor = null; }
        if (!anchor) { log.warn('append anchor #' + before + ' not found in #' + id + ' — appended at the end'); }
      }
      if (anchor) { container.insertBefore(fragment, anchor); }
      else { container.appendChild(fragment); }
      return first.nodeType === 1 ? first : container;
    }

    var ATTR_ALLOW_EXACT = { 'class': true };
    var ATTR_ALLOW_PREFIX = ['aria-', 'data-'];
    function attrNameAllowed(name) {
      if (ATTR_ALLOW_EXACT[name]) return true;
      for (var i = 0; i < ATTR_ALLOW_PREFIX.length; i++) {
        if (name.indexOf(ATTR_ALLOW_PREFIX[i]) === 0) return true;
      }
      return false;
    }

    function removeFragmentElement(id) {
      var el = document.getElementById(id);
      if (!el) { log.warn('Element not found: #' + id); return null; }
      var parent = el.parentNode;
      el.remove();
      return parent || el;
    }

    function applyAttrFragment(f) {
      var el = document.getElementById(f.id);
      if (!el) { log.warn('Element not found: #' + f.id); return null; }
      var name = f.name === undefined || f.name === null ? '' : String(f.name);
      if (!name) {
        warnOnce('attr-no-name', 'attr fragment for #' + f.id + ' missing name — skipped');
        return null;
      }
      if (!attrNameAllowed(name)) {
        warnOnce('attr-name:' + name, 'attr fragment for #' + f.id + ' names "' + name + '" — not on the allowlist, skipped');
        return null;
      }
      var value = f.value === undefined || f.value === null ? '' : String(f.value);
      el.setAttribute(name, value);
      return el;
    }

    function moveFragmentElement(f) {
      var el = document.getElementById(f.id);
      if (!el) { log.warn('Element not found: #' + f.id); return null; }
      var parent = el.parentNode;
      if (!parent) { log.warn('move fragment for #' + f.id + ' has no parent — skipped'); return null; }
      var anchor = null;
      if (f.before) {
        anchor = document.getElementById(f.before);
        if (anchor && anchor.parentNode !== parent) {
          log.warn('move anchor #' + f.before + ' is not a sibling of #' + f.id + ' — appended at the end');
          anchor = null;
        }
        if (!anchor) { log.warn('move anchor #' + f.before + ' not found — appended at the end'); }
      }
      parent.insertBefore(el, anchor);
      return el;
    }

    function applyHotOp(op) {
      if (!op) return false;
      if (op.c === 'text') {
        clearPending(op.id);
        setTextContent(op.id, op.value);
        clearEcho(op.id);
        return true;
      }
      if (op.c === 'attr') {
        if (!attrNameAllowed(op.name)) {
          warnOnce('hot-attr:' + op.name, 'island op attr "' + op.name + '" — not on the allowlist, skipped');
          return false;
        }
        clearPending(op.id);
        applyAttrFragment({ id: op.id, name: op.name, value: op.value });
        return true;
      }
      if (op.c === 'insert') {
        clearPending(op.parent);
        return !!appendChildFragment(op.parent, op.html, op.before || undefined);
      }
      if (op.c === 'remove') {
        clearPending(op.id);
        return !!removeFragmentElement(op.id);
      }
      if (op.c === 'move') {
        clearPending(op.id);
        var moved = moveFragmentElement({ id: op.id, before: op.before || undefined });
        return !!moved;
      }
      return false;
    }

    function armPending(id) {
      var el = document.getElementById(id);
      if (!el) return;
      clearPending(id);
      pending[id] = { html: el.outerHTML, timer: null };
      var record = pending[id];
      record.timer = setTimeout(function () {
        if (!pending[id]) return;
        var saved = pending[id].html;
        delete pending[id];
        replaceElement(id, saved);
        log.warn('optimistic patch for #' + id + ' rolled back (no confirmation)');
      }, settleMs);
    }

    function clearPending(id) {
      var record = pending[id];
      if (!record) return;
      if (record.timer) clearTimeout(record.timer);
      delete pending[id];
    }

    var URL_ATTRS = ['href', 'src', 'action', 'formaction', 'xlink:href'];

    function sanitizeFragment(html, el) {
      var range = document.createRange();
      range.selectNode(el);
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

    function replaceElement(id, html) {
      var el = document.getElementById(id);
      if (!el) {
        log.warn('Element not found: #' + id);
        return;
      }

      var fragment = sanitizeFragment(html, el);

      if (!fragment.firstChild) {
        el.remove();
        log.debug('Removed #' + id);
        return;
      }

      if (el.hasAttribute && el.hasAttribute('data-component-id')) {
        var anchor = null;
        if (el.nodeType === 1) anchor = el.getAttribute('data-component-id');
        var nt = fragment.firstChild.nodeType;
        var wired = nt === 1 && fragment.firstChild.hasAttribute && fragment.firstChild.hasAttribute('data-component-id');
        if (!wired && anchor && !LOST_ANCHOR_WARNED[anchor]) {
          LOST_ANCHOR_WARNED[anchor] = true;
          log.warn('Patch for #' + id + ' dropped routing anchor data-component-id=' + anchor + ' — events on this region are no longer delivered');
        }
      }

      if (onReplace) {
        try { onReplace(el, id); } catch (e) { }
      }
      var savedState = saveInputState(el);

      el.parentNode.replaceChild(fragment, el);

      restoreInputState(id, savedState);

      log.debug('Replaced #' + id);
    }


    function saveInputState(root) {
      var state = {};
      var inputs = root.querySelectorAll('input, textarea, select');
      var active = null;
      try { active = document.activeElement; } catch (e) { active = null; }
      for (var i = 0; i < inputs.length; i++) {
        var el = inputs[i];
        var key = el.id || el.name || i;
        var record = { value: el.value };
        if (el.type === 'checkbox' || el.type === 'radio') {
          record.checked = el.checked;
        }
        try {
          record.selectionStart = el.selectionStart;
          record.selectionEnd = el.selectionEnd;
        } catch (e) { }
        if (active === el) record.focused = true;
        state[key] = record;
        saveScroll(el, el.id || el.name || String(i), state);
      }
      var scrollers = root.querySelectorAll('div, section, ul, ol, main, aside, nav, [tabindex]');
      for (var j = 0; j < scrollers.length; j++) {
        var sc = scrollers[j];
        if (sc.tagName === 'TEXTAREA') continue;
        saveScroll(sc, sc.id || sc.name || '', state);
      }
      saveScroll(root, '__root', state);
      if (active && root.contains(active)) {
        var tag = active.tagName;
        var isForm = tag === 'INPUT' || tag === 'TEXTAREA' || tag === 'SELECT' || tag === 'BUTTON';
        if (!isForm && active.id) {
          state['focus:' + active.id] = { focus: true };
        }
      }
      if (root.tagName === 'DETAILS') {
        state['details:r'] = { open: !!root.open };
      }
      var detailsAll = root.querySelectorAll('details');
      for (var d = 0; d < detailsAll.length; d++) {
        state['details:' + detailsKey(detailsAll[d], d)] = { open: !!detailsAll[d].open };
      }
      return state;
    }

    function detailsKey(el, index) {
      if (el.getAttribute) {
        var k = el.getAttribute('data-webui-key');
        if (k) return 'k:' + k;
        if (el.id) return 'id:' + el.id;
      }
      return 'i:' + index;
    }

    function findDroppedDetail(stateKey) {
      var dk = stateKey.slice(8);
      if (dk.indexOf('k:') === 0) {
        var v = dk.slice(2);
        if (!v || v.indexOf('"') >= 0 || v.indexOf('\\') >= 0) return null;
        try { return document.querySelector('[data-webui-key="' + v + '"]'); } catch (e) { return null; }
      }
      if (dk.indexOf('id:') === 0) return document.getElementById(dk.slice(3));
      return null;
    }

    function retainOpen(fragmentId, stateKey, open) {
      var box = RETAINED_OPEN[fragmentId] || (RETAINED_OPEN[fragmentId] = {});
      box[stateKey] = open;
      var keys = Object.keys(box);
      if (keys.length > 400) {
        var oldest = keys[0];
        delete box[oldest];
        log.debug('evicted retained open state for #' + fragmentId + ' (' + oldest + ')');
      }
    }

    function saveScroll(el, key, state) {
      if (!key) return;
      if (!el.scrollTop && !el.scrollLeft) return;
      state['scroll:' + key] = { sTop: el.scrollTop, sLeft: el.scrollLeft };
    }


    function safeSetSelectionRange(el, start, end) {
      try {
        if (typeof el.setSelectionRange === 'function') {
          el.setSelectionRange(start, end);
        }
      } catch (e) { }
    }

    function restoreInputState(fragmentId, state) {
      if (!state) return;
      var root = document.getElementById(fragmentId);
      if (!root) return;
      var inputs = root.querySelectorAll('input, textarea, select');
      var focusTarget = null;
      var focusState = null;
      for (var i = 0; i < inputs.length; i++) {
        var el = inputs[i];
        var key = el.id || el.name || i;
        var saved = state[key];
        if (saved) {
          if (saved.value !== undefined && el.value !== saved.value) {
            el.value = saved.value;
          }
          if (saved.checked !== undefined && (el.type === 'checkbox' || el.type === 'radio')) {
            el.checked = saved.checked;
          }
          if (saved.selectionStart !== undefined && saved.selectionEnd !== undefined) {
            safeSetSelectionRange(el, saved.selectionStart, saved.selectionEnd);
          }
          if (saved.focused) {
            focusTarget = el;
            focusState = saved;
          }
        }
        var scrollKey = 'scroll:' + (el.id || el.name || String(i));
        if (state[scrollKey]) {
          el.scrollTop = state[scrollKey].sTop;
          el.scrollLeft = state[scrollKey].sLeft;
        }
      }
      for (var sk in state) {
        if (sk.indexOf('scroll:') !== 0) continue;
        var targetId = sk.slice(7);
        if (targetId === '__root') {
          root.scrollTop = state[sk].sTop;
          root.scrollLeft = state[sk].sLeft;
          continue;
        }
        var target = document.getElementById(targetId);
        if (target) {
          target.scrollTop = state[sk].sTop;
          target.scrollLeft = state[sk].sLeft;
        }
      }
      for (var fk in state) {
        if (fk.indexOf('focus:') !== 0) continue;
        var focusEl = document.getElementById(fk.slice(6));
        if (focusEl && typeof focusEl.focus === 'function') {
          try { focusEl.focus(); } catch (e) { }
        }
        break;
      }
      if (focusTarget && typeof focusTarget.focus === 'function') {
        try {
          focusTarget.focus();
          if (focusState && focusState.selectionStart !== undefined && focusState.selectionEnd !== undefined) {
            safeSetSelectionRange(focusTarget, focusState.selectionStart, focusState.selectionEnd);
          }
        } catch (e) { }
      }
      var restoredOpen = {};
      if (root.tagName === 'DETAILS' && state['details:r']) {
        restoredOpen['details:r'] = true;
        if (!!root.open !== !!state['details:r'].open) { root.open = !!state['details:r'].open; }
      }
      var detailsNow = root.querySelectorAll('details');
      for (var dn = 0; dn < detailsNow.length; dn++) {
        var det = detailsNow[dn];
        var dk = 'details:' + detailsKey(det, dn);
        var rec = state[dk];
        if (!rec) continue;
        restoredOpen[dk] = true;
        if (!!det.open !== !!rec.open) { det.open = !!rec.open; }
      }
      var retained = RETAINED_OPEN[fragmentId];
      if (retained) {
        for (var rk in retained) {
          if (restoredOpen[rk]) { delete retained[rk]; continue; }
          var rel = findDroppedDetail(rk);
          if (!rel) continue;
          if (!!rel.open !== !!retained[rk]) { rel.open = !!retained[rk]; }
          delete retained[rk];
        }
        if (!Object.keys(retained).length) delete RETAINED_OPEN[fragmentId];
      }
      for (var ok in state) {
        if (ok.indexOf('details:') !== 0 || restoredOpen[ok]) continue;
        var dk2 = ok.slice(8);
        if (dk2.indexOf('k:') === 0 || dk2.indexOf('id:') === 0) {
          retainOpen(fragmentId, ok, !!state[ok].open);
          continue;
        }
        if (!state[ok].open) continue;
        var warnKey = fragmentId + '|' + ok;
        if (!LOST_OPEN_WARNED[warnKey]) {
          LOST_OPEN_WARNED[warnKey] = true;
          log.warn('Patch for #' + fragmentId + ' dropped a row with captured open state (' + ok + ') — the state cannot be restored');
        }
      }
    }

    function reset() {
      lastSeq = -1;
      for (var id in pending) {
        if (pending.hasOwnProperty(id) && pending[id].timer) {
          clearTimeout(pending[id].timer);
        }
      }
      pending = {};
      queued = [];
      transitionInFlight = false;
      callbackPending = false;
    }

    function setSettle(ms) {
      settleMs = ms;
    }

    return { patch: patch, reset: reset, setSettle: setSettle, sanitize: sanitizeFragment, echo: echo, echoOverlay: echoOverlay, applyHotOp: applyHotOp, setOnReplace: setOnReplace };

    function setOnReplace(fn) {
      onReplace = fn;
    }
  }

  var UNSAFE_PROTOCOLS = /^(javascript|data|vbscript):/i;

  function stripUrlControlChars(url) {
    return String(url).replace(/[\u0000-\u0020\u007F]/g, '');
  }

  function isSafeUrl(url) {
    return !UNSAFE_PROTOCOLS.test(stripUrlControlChars(url));
  }

  function createRouter(log) {
    return {
      navigate: function (url) {
        if (!url) return;
        var clean = stripUrlControlChars(url);
        if (!isSafeUrl(clean)) { log.warn('Router.navigate: blocked unsafe URL'); return; }
        history.pushState(null, '', clean);
      },

      redirect: function (url, replace) {
        if (!url) return;
        var clean = stripUrlControlChars(url);
        if (!isSafeUrl(clean)) { log.warn('Router.redirect: blocked unsafe URL'); return; }
        if (replace) location.replace(clean);
        else location.href = clean;
      },

      reload: function () { location.reload(); },
    };
  }

  function createStateStore(log) {
    var store = {};
    var subscribers = {};

    var PROTO_DENY = { '__proto__': true, 'constructor': true, 'prototype': true };

    function isSafeKey(key) {
      return !PROTO_DENY.hasOwnProperty(key);
    }

    function get(path) {
      if (!path) return undefined;
      var parts = path.split('.');
      var current = store;
      for (var i = 0; i < parts.length; i++) {
        if (current === undefined || current === null) return undefined;
        if (!isSafeKey(parts[i])) return undefined;
        current = current[parts[i]];
      }
      return current;
    }

    function set(path, value) {
      if (!path) return;
      var parts = path.split('.');

      for (var i = 0; i < parts.length; i++) {
        if (!isSafeKey(parts[i])) {
          log.warn('State.set: denied key "' + parts[i] + '" in path "' + path + '"');
          return;
        }
      }
      var current = store;
      for (var i = 0; i < parts.length - 1; i++) {
        if (!current[parts[i]] || typeof current[parts[i]] !== 'object') {
          current[parts[i]] = {};
        }
        current = current[parts[i]];
      }
      current[parts[parts.length - 1]] = value;
      notify(path, value);
    }

    function subscribe(path, callback) {
      if (!path || typeof callback !== 'function') return function () {};
      if (!subscribers[path]) subscribers[path] = [];
      subscribers[path].push(callback);
      return function () {
        var subs = subscribers[path];
        if (subs) {
          var idx = subs.indexOf(callback);
          if (idx !== -1) subs.splice(idx, 1);
        }
      };
    }

    function notify(path, value) {
      var subs = subscribers[path];
      if (subs) {

        var copy = subs.slice();
        for (var i = 0; i < copy.length; i++) {
          try { copy[i](value, path); } catch (e) { log.error('State subscriber error: ' + e.message); }
        }
      }
    }

    function clear() { store = {}; subscribers = {}; }

    return { get: get, set: set, subscribe: subscribe, clear: clear };
  }

  function createMessageDispatcher(log, fragmentPatcher, stateStore, router, config) {
    return function handleMessage(msg) {
      if (!msg || !msg.type) {
        log.warn('Received message without type');
        return;
      }

      switch (msg.type) {
        case 'update':
          fragmentPatcher.patch(msg.fragments, msg.seq);
          restoreModalFocus();
          break;

        case 'redirect':
          router.redirect(msg.url, msg.replace === true);
          break;

        case 'state':
          if (msg.path) stateStore.set(msg.path, msg.value);
          break;

        case 'reload':
          router.reload();
          break;

        case 'error':
          log.error('Server error [' + (msg.code || 'UNKNOWN') + ']: ' + (msg.message || 'No message'));
          break;

        case 'pong':

          break;

        case 'token':
          if (msg.token) config.renderToken = msg.token;
          break;

        default:
          log.warn('Unknown message type: ' + msg.type);
          break;
      }
    };
  }

  function dispatchEvent(name, detail) {
    try {
      document.dispatchEvent(new CustomEvent(name, { detail: detail }));
    } catch (e) {  }
  }

  var instance = null;

  var modalFocus = null;
  function focusablesIn(root) {
    var sel = 'button, [href], input, select, textarea, [tabindex], summary';
    var list = [];
    var all = root.querySelectorAll(sel);
    for (var i = 0; i < all.length; i++) {
      var el = all[i];
      if (!el.disabled && el.getAttribute('tabindex') !== '-1') list.push(el);
    }
    return list;
  }
  function restoreModalFocus() {
    if (!modalFocus) return;
    var opener = modalFocus;
    modalFocus = null;
    if (document.querySelector('.modal-overlay')) return;
    if (opener && typeof opener.focus === 'function') {
      try { opener.focus(); } catch (e) { }
    }
  }
  document.addEventListener('focusout', function (e) {
    var from = e.target;
    var to = e.relatedTarget;
    if (!from || !from.closest) return;
    var fromModal = from.closest('.modal-overlay');
    var toModal = to && to.closest ? to.closest('.modal-overlay') : null;
    if (!fromModal && toModal) { modalFocus = from; }
  }, true);
  document.addEventListener('keydown', function (e) {
    if (e.key !== 'Tab') return;
    if (!e.target || !e.target.closest) return;
    var modal = e.target.closest('.modal-overlay');
    if (!modal) return;
    var f = focusablesIn(modal);
    if (!f.length) return;
    if (e.shiftKey && e.target === f[0]) { e.preventDefault(); f[f.length - 1].focus(); }
    else if (!e.shiftKey && e.target === f[f.length - 1]) { e.preventDefault(); f[0].focus(); }
  }, true);

  var _islandSanitize = null;
  var _islandConfig = null;
  var _islandApply = null;
  var islandModules = {};
  var islandLoading = {};
  var islandRegionState = {};
  var islandRafHosts = [];
  var islandRafGoing = false;
  var ISLAND_HOST = {
    webui_log: function (h) { return function (p, l) { var t = islandStr(h, p, l); if (t !== null) { try { console.log('[island:' + h.name + '] ' + t); } catch (e) { } } return 0; }; },
    webui_now_ms: function () { return function () { return (typeof performance === 'undefined' || !performance.now) ? Date.now() : performance.now(); }; },
    webui_raf: function (h) { return function (i) { islandRafRegister(h, i); return 0; }; },
    webui_store_get: function (h) { return function (p, l) { var k = islandStr(h, p, l); if (!k) return 0; var v = null; try { v = window.localStorage.getItem(k); } catch (e) { } return (v === null) ? 0 : islandFrameWrite(h, v); }; },
    webui_store_set: function (h) { return function (kp, kl, vp, vl) { var k = islandStr(h, kp, kl); if (k === null) return 0; var v = (vp === undefined) ? '' : (islandStr(h, vp, vl) || ''); try { window.localStorage.setItem(k, v); } catch (e) { } return 0; }; },
    webui_surface: function () { return function () { return 0; }; },
  };
  function islandStr(h, p, l) { var m = h.exports && h.exports.memory; return (m && l) ? new TextDecoder().decode(new Uint8Array(m.buffer, p, l)) : null; }
  function buildImports(module, host) {
    var imports = {};
    var declared = WebAssembly.Module.imports(module);
    for (var i = 0; i < declared.length; i++) {
      var imp = declared[i];
      var bucket = imports[imp.module] || (imports[imp.module] = {});
      if (imp.name.indexOf('webui_') === 0 && !ISLAND_HOST[imp.name]) { throw new Error('island imports unknown host fn ' + imp.name); }
      bucket[imp.name] = ISLAND_HOST[imp.name] ? ISLAND_HOST[imp.name](host) : function () { return 0; };
    }
    return imports;
  }
  function islandFrameWrite(h, text) {
    var e = h.exports;
    if (!e || typeof e.webui_frame_ptr !== 'function') return 0;
    var m = e.memory;
    var ptr = e.webui_frame_ptr();
    var b = new TextEncoder().encode(text);
    var cap = m.buffer.byteLength - ptr - 4;
    if (cap < 0) return 0;
    if (b.length > cap) { b = b.slice(0, cap); }
    var w = new Uint8Array(m.buffer, ptr, b.length + 4);
    w[0] = b.length & 255; w[1] = (b.length >>> 8) & 255; w[2] = (b.length >>> 16) & 255; w[3] = b.length >>> 24;
    w.set(b, 4);
    return ptr;
  }
  function islandRafRegister(h, i) {
    if (typeof requestAnimationFrame !== 'function') { return; }
    (h.raf = h.raf || {})[i] = true;
    if (islandRafHosts.indexOf(h) === -1) { islandRafHosts.push(h); }
    if (!islandRafGoing) { islandRafGoing = true; requestAnimationFrame(islandRafTick); }
  }
  function islandRafTick() {
    islandRafGoing = false;
    var live = [];
    for (var i = 0; i < islandRafHosts.length; i++) {
      var h = islandRafHosts[i];
      var idx = [];
      for (var k in h.raf) { if (h.raf[k]) { idx.push(Number(k)); h.raf[k] = false; } }
      if (!idx.length) { continue; }
      live.push(h);
      var ex = h.exports;
      if (ex && typeof ex.webui_frame_tick === 'function') {
        for (var j = 0; j < idx.length; j++) {
          try { ex.webui_frame_tick(idx[j]); } catch (e) { }
          if (_islandApply) { drainIslandOps(h.name, ex); }
        }
      }
    }
    islandRafHosts = live;
    if (islandRafHosts.length) { islandRafGoing = true; requestAnimationFrame(islandRafTick); }
  }
  function instantiateIsland(module, name) {
    var host = { exports: null, name: name };
    return WebAssembly.instantiate(module, buildImports(module, host)).then(function (result) {
      var inst = result && result.instance ? result.instance : result;
      host.exports = inst.exports;
      return inst.exports;
    });
  }
  function ensureIslandMemory(exports) {
    var target = 8 * 1024 * 1024;
    if (!exports.memory || exports.memory.buffer.byteLength >= target) { return; }
    var grow = exports.memory.grow;
    if (typeof grow !== 'function') { return; }
    var pages = Math.ceil((target - exports.memory.buffer.byteLength) / 65536);
    try { grow(pages); } catch (e) { }
  }
  function islandState(el, state) {
    el.setAttribute('data-webui-island-state', state);
  }
  function islandRender(el, name) {
    var mod = islandModules[name];
    if (!mod || !mod.exports || !mod.exports.webui_render_region) {
      islandState(el, 'unmapped');
      return false;
    }
    restoreIslandRegionState(el, name);
    var args = {};
    try { args = JSON.parse(el.getAttribute('data-webui-args') || '{}'); } catch (e) { }
    var payload = new TextEncoder().encode(JSON.stringify({ name: name, args: args }));
    if (payload.length > 65536) { islandState(el, 'unmapped'); return false; }
    var ptr = mod.exports.webui_input_ptr();
    new Uint8Array(mod.memory.buffer, ptr, payload.length).set(payload);
    var outPtr = mod.exports.webui_render_region(ptr, payload.length);
    var outLen = mod.exports.webui_frame_len();
    if (!outPtr || outLen === 0) { islandState(el, 'unmapped'); return false; }
    var html = new TextDecoder().decode(new Uint8Array(mod.memory.buffer, outPtr, outLen));
    while (el.firstChild) { el.removeChild(el.firstChild); }
    if (_islandSanitize) {
      el.appendChild(_islandSanitize(html, el));
    } else {
      el.innerHTML = html;
    }
    islandState(el, 'mounted');
    return true;
  }
  function loadIsland(name) {
    if (islandModules[name]) { return Promise.resolve(islandModules[name]); }
    if (islandLoading[name]) { return islandLoading[name]; }
    var url = '/__assets/webui-' + name + '.wasm';
    islandLoading[name] = fetch(url)
      .then(function (r) { if (!r.ok) { throw new Error('island fetch ' + r.status); } return r; })
      .then(function (res) {
        if (typeof WebAssembly.compileStreaming === 'function' && res && res.body) {
          return WebAssembly.compileStreaming(Promise.resolve(res));
        }
        return res.arrayBuffer().then(function (bytes) { return new WebAssembly.Module(bytes); });
      })
      .then(function (mod) { return instantiateIsland(mod, name); })
      .then(function (exports) {
        if (!exports) { return null; }
        if (typeof exports._start === 'function') {
          try { exports._start(); } catch (e) { }
        }
        ensureIslandMemory(exports);
        islandModules[name] = { exports: exports, memory: exports.memory };
        return islandModules[name];
      })
      .catch(function (err) {
        islandLoading[name] = null;
        if (err && err.message) {
          _islandLog('island ' + name + ' unavailable (' + err.message + '); page stays server-rendered', 'warn');
        }
        return null;
      });
    return islandLoading[name];
  }
  function drainIslandOps(name, ex) {
    if (typeof ex.webui_take_ops !== 'function') { return 0; }
    var applied = 0;
    var batches = 0;
    while (++batches <= 64) {
      var len = 0;
      try { len = ex.webui_take_ops(); } catch (e) { _islandLog('island ' + name + ' webui_take_ops threw: ' + e.message, 'warn'); break; }
      if (!len || len > 262144) { break; }
      var bytes = (function () {
        try { return new Uint8Array(ex.memory.buffer, ex.webui_frame_ptr(), len).slice(); }
        catch (e) { return null; }
      })();
      if (!bytes) { _islandLog('island ' + name + ' webui_take_ops frame out of bounds — drain stopped', 'warn'); break; }
      var at = 0;
      var good = true;
      while (at < bytes.length) {
        var rec = null;
        try { rec = decodeHotOpRecord(bytes, at); } catch (e) { good = false; break; }
        if (!rec || !_islandApply) { good = false; break; }
        _islandApply(rec.op);
        applied++;
        at = rec.next;
      }
      if (!good) { _islandLog('island ' + name + ' emitted a malformed op record — drain stopped', 'warn'); break; }
    }
    return applied;
  }
  function decodeHotOpRecord(bytes, start) {
    var p = start;
    var td = new TextDecoder();
    function take(n) { if (p + n > bytes.length) { throw new RangeError('trunc'); } var s = p; p += n; return s; }
    function u8() { return bytes[take(1)]; }
    function u16() { var s = take(2); return bytes[s] | (bytes[s + 1] << 8); }
    function u32() { var s = take(4); return bytes[s] | (bytes[s + 1] << 8) | (bytes[s + 2] << 16) | (bytes[s + 3] * 16777216); }
    function id16() { var n = u16(); return td.decode(bytes.subarray(take(n), p)); }
    function id32() { var n = u32(); return td.decode(bytes.subarray(take(n), p)); }
    function optId() { var n = u16(); if (n === 0xffff) { return null; } return td.decode(bytes.subarray(take(n), p)); }
    if (u8() !== 1) { throw new RangeError('ver'); }
    var op = u8();
    var eid = id16();
    var r = null;
    if (op === 1) { r = { c: 'text', id: eid, value: id32() }; }
    else if (op === 2) { r = { c: 'attr', id: eid, name: id16(), value: id32() }; }
    else if (op === 3) { r = { c: 'insert', parent: eid, before: optId(), html: id32() }; }
    else if (op === 4) { r = { c: 'remove', id: eid }; }
    else if (op === 5) { r = { c: 'move', id: eid, before: optId() }; }
    else { throw new RangeError('op' + op); }
    return { op: r, next: p };
  }
  function mountIslandRegion(el) {
    if (el.getAttribute('data-webui-island-state') === 'mounted') { return; }
    var name = el.getAttribute('data-webui-island');
    if (!name) { return; }
    if (_islandConfig && _islandConfig.capabilities && _islandConfig.capabilities.indexOf(name) === -1) {
      islandState(el, 'unmapped');
      return;
    }
    var ref = el;
    loadIsland(name).then(function (mod) {
      if (mod) { islandRender(ref, name); }
      else { islandState(ref, 'unmapped'); }
    });
  }
  function mountAllIslands() {
    var regions = document.querySelectorAll('[data-webui-island]');
    for (var i = 0; i < regions.length; i++) { mountIslandRegion(regions[i]); }
  }
  function wireIslandInputs() {
    document.addEventListener('input', function (e) {
      var t = e.target;
      if (!t || !t.getAttribute) { return; }
      var regionId = t.getAttribute('data-island-input');
      if (!regionId) { return; }
      var region = document.getElementById(regionId);
      if (!region || !region.getAttribute) { return; }
      if (islandRegionSubscribed(region, 'input')) { return; }
      var name = region.getAttribute('data-webui-island');
      if (!name || !islandModules[name]) { return; }
      var args = {};
      try { args = JSON.parse(region.getAttribute('data-webui-args') || '{}'); } catch (err) { }
      args.value = t.value;
      region.setAttribute('data-webui-args', JSON.stringify(args));
      islandRender(region, name);
    });
  }
  function islandRegionSubscribed(region, type) {
    var raw = region.getAttribute('data-webui-island-events');
    if (!raw) { return false; }
    var list = null;
    try { list = JSON.parse(raw); } catch (e) { return false; }
    if (!Array.isArray(list)) { return false; }
    if (list.indexOf(type) !== -1) { return true; }
    if (type === 'focusin' && list.indexOf('focus') !== -1) { return true; }
    if (type === 'focusout' && list.indexOf('blur') !== -1) { return true; }
    return false;
  }
  function saveIslandRegionState(el) {
    if (!el || !el.getAttribute) { return; }
    var name = el.getAttribute('data-webui-island');
    if (!name) { return; }
    var mod = islandModules[name];
    if (!mod || !mod.exports || typeof mod.exports.webui_state_save !== 'function') { return; }
    try {
      var ptr = mod.exports.webui_state_save();
      var len = (typeof mod.exports.webui_frame_len === 'function') ? mod.exports.webui_frame_len() : 0;
      if (!ptr || !len) { return; }
      islandRegionState[name + '|' + (el.id || '')] = new Uint8Array(mod.memory.buffer, ptr, len).slice();
    } catch (e) { _islandLog('island ' + name + ' webui_state_save threw: ' + e.message, 'warn'); }
  }
  function restoreIslandRegionState(el, name) {
    var mod = islandModules[name];
    if (!mod || !mod.exports || typeof mod.exports.webui_state_restore !== 'function') { return false; }
    var bytes = islandRegionState[name + '|' + (el.id || '')];
    if (!bytes || !bytes.length || bytes.length > 65536) { return false; }
    var inputPtr = mod.exports.webui_input_ptr();
    new Uint8Array(mod.memory.buffer, inputPtr, bytes.length).set(bytes);
    try { mod.exports.webui_state_restore(inputPtr, bytes.length); } catch (e) { _islandLog('island ' + name + ' webui_state_restore threw: ' + e.message, 'warn'); }
    return true;
  }
  function saveAllIslandRegions() {
    var els = document.querySelectorAll('[data-webui-island]');
    for (var i = 0; i < els.length; i++) { saveIslandRegionState(els[i]); }
  }
  function reconcileIslandRegions(changed) {
    for (var i = 0; i < changed.length; i++) {
      var n = changed[i];
      if (!n || n.nodeType !== 1 || !n.getAttribute) { continue; }
      if (n.getAttribute('data-webui-island')) { mountIslandRegion(n); continue; }
      if (n.querySelectorAll) {
        var inner = n.querySelectorAll('[data-webui-island]');
        for (var j = 0; j < inner.length; j++) { mountIslandRegion(inner[j]); }
      }
    }
  }
  function _islandLog(msg, level) {
    try {
      if (level === 'warn') { console.warn('[WebUIEngine] ' + msg); }
      else { console.log('[WebUIEngine] ' + msg); }
    } catch (e) { }
  }
  var _statusEl = null;
  var _statusText = null;
  var _statusTimer = null;
  function ensureStatus() {
    if (_statusEl || !document.body) { return; }
    if (document.querySelector('[data-webui-status]')) { return; }
    _statusEl = document.createElement('div');
    _statusEl.className = 'engine-status';
    _statusEl.setAttribute('role', 'status');
    _statusEl.style.display = 'none';
    var dot = document.createElement('span');
    dot.className = 'engine-status__dot';
    var text = document.createElement('span');
    text.className = 'engine-status__text';
    text.textContent = 'reconnecting\u2026';
    _statusEl.appendChild(dot);
    _statusEl.appendChild(text);
    _statusText = text;
    document.body.appendChild(_statusEl);
  }
  document.addEventListener('webui:disconnected', function () {
    ensureStatus();
    if (!_statusEl) { return; }
    if (_statusTimer) { clearTimeout(_statusTimer); }
    _statusTimer = setTimeout(function () {
      _statusEl.className = 'engine-status engine-status--visible';
      _statusEl.style.display = 'inline-flex';
    }, 400);
    updateStatusMirrors('reconnecting');
  });
  document.addEventListener('webui:connected', function () {
    if (_statusTimer) { clearTimeout(_statusTimer); _statusTimer = null; }
    if (_statusEl) {
      _statusEl.className = 'engine-status';
      _statusEl.style.display = 'none';
    }
    updateStatusMirrors('connected');
  });

  function updateStatusMirrors(state) {
    var els = document.querySelectorAll('[data-webui-status]');
    for (var i = 0; i < els.length; i++) {
      els[i].setAttribute('data-webui-state', state);
    }
    if (_statusText) {
      _statusText.textContent = state === 'connected' ? 'connected' : 'reconnecting\u2026';
    }
  }


  function init(opts) {
    if (instance) {
      console.warn('[WebUIEngine] Already initialized');
      return;
    }

    var config = {};
    for (var key in DEFAULTS) {
      if (DEFAULTS.hasOwnProperty(key)) {
        config[key] = (opts && opts[key] !== undefined) ? opts[key] : DEFAULTS[key];
      }
    }

    var log = createLogger(config.logLevel);
    log.info('Initializing WebUI Engine v1.0');

    var stateStore = createStateStore(log);
    var fragmentPatcher = createFragmentPatcher(log);
    var router = createRouter(log);
    var handleMessage = createMessageDispatcher(log, fragmentPatcher, stateStore, router, config);
    var wsClient = createWSClient(log, handleMessage);
    var eventDelegator = createEventDelegator(log, wsClient.send, fragmentPatcher);

    wsClient.reset(config);
    eventDelegator.reset(config);
    fragmentPatcher.setSettle(config.optimisticSettleMs);

    _islandSanitize = fragmentPatcher.sanitize;
    _islandConfig = config;
    _islandApply = fragmentPatcher.applyHotOp;
    fragmentPatcher.setOnReplace(function (el) { saveIslandRegionState(el); });
    afterPatchHooks.push(reconcileIslandRegions);
    document.addEventListener('webui:connected', saveAllIslandRegions);

    eventDelegator.mount();

    hookLog = log;
    wsClient.connect();

    var bootIslands = function () {
      ensureStatus();
      if (_islandConfig && _islandConfig.capabilities && _islandConfig.capabilities.indexOf('offline') !== -1 && navigator.serviceWorker) {
        navigator.serviceWorker.register('/ui/webui-shell.js', { scope: '/' }).catch(function () { });
      }
      window.addEventListener('online', function () {
        if (instance && instance.wsClient) { instance.wsClient.connect(); }
      });
      wireIslandInputs(); mountAllIslands();
    };
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', bootIslands);
    } else {
      bootIslands();
    }

    var popstateHandler = function () {
      wsClient.send({ type: 'navigate', url: location.pathname + location.search });
    };
    window.addEventListener('popstate', popstateHandler);

    instance = {
      config: config,
      log: log,
      wsClient: wsClient,
      eventDelegator: eventDelegator,
      fragmentPatcher: fragmentPatcher,
      patch: fragmentPatcher.patch,
      stateStore: stateStore,
      popstateHandler: popstateHandler,
    };

    runHooks(readyHooks, document);

    log.info('WebUI Engine initialized');
  }


  function destroy() {
    if (!instance) return;
    instance.log.info('Destroying WebUI Engine');
    if (instance.popstateHandler) {
      window.removeEventListener('popstate', instance.popstateHandler);
    }
    instance.wsClient.disconnect();
    instance.eventDelegator.unmount();
    instance.fragmentPatcher.setOnReplace(null);
    instance.fragmentPatcher.reset();
    instance.stateStore.clear();
    instance = null;
  }

  window.addEventListener('beforeunload', destroy);

  return {
    init: init,
    destroy: destroy,

    on: {
      afterPatch: function (fn) { if (typeof fn === 'function') { afterPatchHooks.push(fn); } },
      ready: function (fn) { if (typeof fn === 'function') { readyHooks.push(fn); } },
    },

    _reset: function () { instance = null; },
    _getInstance: function () { return instance; },
  };
})();

(function () {
  var meta = document.querySelector('meta[name="webui-config"]');
  if (!meta) return;
  var raw = meta.getAttribute('content');
  if (!raw) return;
  var cfg;
  try { cfg = JSON.parse(raw); } catch (e) { return; }
  window.WebUIEngine.init(cfg);
})();
