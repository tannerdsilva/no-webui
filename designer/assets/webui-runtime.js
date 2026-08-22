
window.WebUIRuntime = (function () {
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
    logLevel: 'warn',
  };

  var LOG_LEVELS = { debug: 0, info: 1, warn: 2, error: 3, silent: 4 };
  var EVENT_TYPES = ['click', 'input', 'change', 'submit', 'keydown', 'focus', 'blur'];

  function createLogger(level) {
    var min = LOG_LEVELS[level] || LOG_LEVELS.warn;
    return {
      debug: function (msg) { if (LOG_LEVELS.debug >= min) console.log('[WebUIRuntime] ' + msg); },
      info:  function (msg) { if (LOG_LEVELS.info >= min)  console.info('[WebUIRuntime] ' + msg); },
      warn:  function (msg) { if (LOG_LEVELS.warn >= min)  console.warn('[WebUIRuntime] ' + msg); },
      error: function (msg) { if (LOG_LEVELS.error >= min) console.error('[WebUIRuntime] ' + msg); },
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
          messageQueue.shift(); // drop oldest
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
          ws.send(JSON.stringify({ type: 'ping' }));

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

  function createEventDelegator(log, send) {
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
        if (inputTimers.hasOwnProperty(key)) clearTimeout(inputTimers[key]);
      }
      inputTimers = {};
      log.debug('Event delegation unmounted');
    }

    function handleEvent(event) {
      var componentEl = findComponent(event);
      if (!componentEl) return;

      var componentId = componentEl.getAttribute('data-component-id');
      if (!componentId) return;

      if (event.type === 'click') {
        if (event.metaKey || event.ctrlKey || event.shiftKey) return; // let browser handle
        var link = event.target.closest('a');
        if (link) {

          if (link.hasAttribute('download')) return;
          if (link.getAttribute('href') && link.getAttribute('href').startsWith('#')) return;
          if (link.getAttribute('target') === '_blank') return;
          event.preventDefault();
        }
      }

      if (event.type === 'keydown' && event.key === 'Enter') {
        if (componentEl.getAttribute('data-prevent-enter') !== 'false') {
          event.preventDefault();
        }
      }

      if (event.type === 'submit') {
        event.preventDefault();
      }

      var eventData = extractEventData(event, componentEl);

      if (event.type === 'input') {
        debounceInput(componentId, event, eventData);
        return;
      }

      send({
        type: 'event',
        component: componentId,
        event: event.type,
        data: eventData,
      });
    }


    function findComponent(event) {
      var path = [];
      if (typeof event.composedPath === 'function') {
        path = event.composedPath();
      } else {
        var el = event.target;
        while (el && el !== document) {
          path.push(el);
          el = el.parentElement;
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

    function extractEventData(event, componentEl) {
      var target = event.target;
      switch (event.type) {
        case 'click':
          return {};

        case 'input':
        case 'change':
          if (target.type === 'checkbox' || target.type === 'radio') {
            return { value: target.value, checked: target.checked };
          }
          return { value: target.value || '' };

        case 'submit':
          return extractFormData(target);

        case 'keydown':
          return {
            key: event.key,
            ctrlKey: String(event.ctrlKey),
            shiftKey: String(event.shiftKey),
            altKey: String(event.altKey),
            metaKey: String(event.metaKey),
          };

        case 'focus':
        case 'blur':
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
          data[el.name] = values;
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

      if (inputTimers[key]) {
        clearTimeout(inputTimers[key]);
      }

      if (!inputTimers[key + ':leading']) {
        inputTimers[key + ':leading'] = true;
        send({
          type: 'event',
          component: componentId,
          event: event.type,
          data: eventData,
        });

        inputTimers[key + ':reset'] = setTimeout(function () {
          delete inputTimers[key + ':leading'];
          delete inputTimers[key + ':reset'];
        }, config.debounceMaxWaitMs);
        return;
      }

      inputTimers[key] = setTimeout(function () {
        delete inputTimers[key];
        send({
          type: 'event',
          component: componentId,
          event: event.type,
          data: eventData,
        });
      }, config.debounceInputMs);
    }

    function reset(config_) {
      config = config_;
    }

    return { mount: mount, unmount: unmount, reset: reset };
  }

  function createFragmentPatcher(log) {
    var lastSeq = -1;


    function patch(fragments, seq) {
      if (!fragments || !fragments.length) return;

      if (seq !== undefined && seq !== null) {
        if (seq <= lastSeq) {
          log.warn('Dropping duplicate/out-of-order update seq=' + seq + ' (last=' + lastSeq + ')');
          return;
        }
        lastSeq = seq;
      }

      log.debug('Patching ' + fragments.length + ' fragment(s)' + (seq !== undefined ? ' seq=' + seq : ''));

      for (var i = 0; i < fragments.length; i++) {
        var f = fragments[i];
        if (!f.id || f.html === undefined) {
          log.warn('Invalid fragment at index ' + i);
          continue;
        }
        replaceElement(f.id, f.html);
      }
    }

    function sanitizeFragmentHTML(html) {

      html = html.replace(new RegExp('<script[^<]*(?:<[^<]*)*' + '<' + '/script>', 'gi'), '');

      html = html.replace(new RegExp("\\s+on\\w+\\s*=\\s*(?:\"[^\"]*\"|'[^']*'|[^\\s>]+)", 'gi'), '');

      html = html.replace(new RegExp('\\s+(href|src|action|formaction|xlink:href)\\s*=\\s*"javascript:[^"]*"', 'gi'), ' $1=""');
      html = html.replace(new RegExp("\\s+(href|src|action|formaction|xlink:href)\\s*=\\s*'javascript:[^']*'", 'gi'), " $1=''");
      return html;
    }

    function replaceElement(id, html) {
      var el = document.getElementById(id);
      if (!el) {
        log.warn('Element not found: #' + id);
        return;
      }

      html = sanitizeFragmentHTML(html);

      var savedState = saveInputState(el);

      var range = document.createRange();
      range.selectNode(el);
      var fragment = range.createContextualFragment(html);
      el.parentNode.replaceChild(fragment, el);

      restoreInputState(id, savedState);

      log.debug('Replaced #' + id);
    }


    function saveInputState(root) {
      var state = {};
      var inputs = root.querySelectorAll('input, textarea, select');
      for (var i = 0; i < inputs.length; i++) {
        var el = inputs[i];
        var key = el.id || el.name || i;
        state[key] = {
          value: el.value,
          checked: el.type === 'checkbox' || el.type === 'radio' ? el.checked : undefined,
          selectionStart: el.selectionStart,
          selectionEnd: el.selectionEnd,
        };
      }
      return state;
    }


    function restoreInputState(fragmentId, state) {
      if (!state) return;
      var root = document.getElementById(fragmentId);
      if (!root) return;
      var inputs = root.querySelectorAll('input, textarea, select');
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
            el.setSelectionRange(saved.selectionStart, saved.selectionEnd);
          }
        }
      }
    }

    function reset() { lastSeq = -1; }

    return { patch: patch, reset: reset };
  }

  var UNSAFE_PROTOCOLS = /^(javascript|data|vbscript):/i;

  function isSafeUrl(url) {

    return !UNSAFE_PROTOCOLS.test(url);
  }

  var Router = {
    navigate: function (url) {
      if (!url) return;
      if (!isSafeUrl(url)) { log.warn('Router.navigate: blocked unsafe URL'); return; }
      history.pushState(null, '', url);
    },

    redirect: function (url, replace) {
      if (!url) return;
      if (!isSafeUrl(url)) { log.warn('Router.redirect: blocked unsafe URL'); return; }
      if (replace) location.replace(url);
      else location.href = url;
    },

    reload: function () { location.reload(); },
  };

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

  function createMessageDispatcher(log, fragmentPatcher, stateStore) {
    return function handleMessage(msg) {
      if (!msg || !msg.type) {
        log.warn('Received message without type');
        return;
      }

      switch (msg.type) {
        case 'update':
          fragmentPatcher.patch(msg.fragments, msg.seq);
          break;

        case 'redirect':
          Router.redirect(msg.url, msg.replace === true);
          break;

        case 'state':
          if (msg.path) stateStore.set(msg.path, msg.value);
          break;

        case 'reload':
          Router.reload();
          break;

        case 'error':
          log.error('Server error [' + (msg.code || 'UNKNOWN') + ']: ' + (msg.message || 'No message'));
          break;

        case 'pong':

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


  function init(opts) {
    if (instance) {
      console.warn('[WebUIRuntime] Already initialized');
      return;
    }

    var config = {};
    for (var key in DEFAULTS) {
      if (DEFAULTS.hasOwnProperty(key)) {
        config[key] = (opts && opts[key] !== undefined) ? opts[key] : DEFAULTS[key];
      }
    }

    var log = createLogger(config.logLevel);
    log.info('Initializing WebUI Runtime v0.2');

    var stateStore = createStateStore(log);
    var fragmentPatcher = createFragmentPatcher(log);
    var handleMessage = createMessageDispatcher(log, fragmentPatcher, stateStore);
    var wsClient = createWSClient(log, handleMessage);
    var eventDelegator = createEventDelegator(log, wsClient.send);

    wsClient.reset(config);
    eventDelegator.reset(config);

    eventDelegator.mount();

    wsClient.connect();

    window.addEventListener('popstate', function () {
      wsClient.send({ type: 'navigate', url: location.pathname + location.search });
    });

    instance = {
      config: config,
      log: log,
      wsClient: wsClient,
      eventDelegator: eventDelegator,
      fragmentPatcher: fragmentPatcher,
      stateStore: stateStore,
    };

    log.info('WebUI Runtime initialized');
  }


  function destroy() {
    if (!instance) return;
    instance.log.info('Destroying WebUI Runtime');
    instance.wsClient.disconnect();
    instance.eventDelegator.unmount();
    instance.fragmentPatcher.reset();
    instance.stateStore.clear();
    instance = null;
  }

  window.addEventListener('beforeunload', destroy);

  return {
    init: init,
    destroy: destroy,

    _reset: function () { instance = null; },
    _getInstance: function () { return instance; },
  };
})();
