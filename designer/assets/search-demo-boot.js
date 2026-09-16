(function () {
  if (!window.WebUIClient) { return; }
  var meta = document.querySelector('meta[name="webui-wasm"]');
  var wasmUrl = (meta && meta.getAttribute('content')) || '/__assets/app.wasm';
  WebUIClient.boot({ wasmUrl: wasmUrl, mode: 'search', target: 'search-app' }).then(function (page) {
    document.dispatchEvent(new CustomEvent('webui:search-ready', { detail: { bytes: page.length } }));
  }).catch(function (err) {
    window.__webuiSearchError = String(err);
    var el = document.getElementById('search-app');
    if (el) { el.setAttribute('data-boot', 'load-error'); }
    document.dispatchEvent(new CustomEvent('webui:search-error', { detail: String(err) }));
  });
})();
