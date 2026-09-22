'use strict';
var CACHE = 'webui-shell-v1';
self.addEventListener('install', function (e) {
  e.waitUntil(
    caches.open(CACHE).then(function (c) {
      return Promise.all([
        c.add('/ui/webui-engine.js'),
        c.add('/__assets/css')
      ]).catch(function () {});
    })
  );
  self.skipWaiting();
});
self.addEventListener('activate', function (e) {
  e.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.map(function (k) {
        if (k !== CACHE) { return caches.delete(k); }
        return null;
      }));
    }).then(function () { return self.clients.claim(); })
  );
});
self.addEventListener('fetch', function (e) {
  var url;
  try { url = new URL(e.request.url); } catch (err) { return; }
  if (e.request.mode === 'navigate') {
    e.respondWith(
      fetch(e.request).catch(function () { return caches.match(e.request); })
    );
    return;
  }
  if (url.pathname.indexOf('/__assets/') === 0) {
    e.respondWith(
      caches.open(CACHE).then(function (c) {
        return c.match(e.request).then(function (hit) {
          if (hit) { return hit; }
          return fetch(e.request).then(function (r) {
            if (r.ok) { c.put(e.request, r.clone()); }
            return r;
          });
        });
      })
    );
    return;
  }
  if (url.pathname === '/ui/webui-engine.js' || url.pathname === '/__assets/css') {
    e.respondWith(
      caches.match(e.request).then(function (hit) { return hit || fetch(e.request); })
    );
    return;
  }
});
