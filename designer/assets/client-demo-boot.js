(function () {
  if (!window.WebUIClient) { return; }
  var meta = document.querySelector('meta[name="webui-wasm"]');
  var wasmUrl = (meta && meta.getAttribute('content')) || '/__assets/app.wasm';
  WebUIClient.boot({ wasmUrl: wasmUrl, target: 'app' }).then(function (html) {
    document.dispatchEvent(new CustomEvent('webui:client-ready', { detail: { bytes: html.length } }));
  }).catch(function (err) {
    window.__webuiClientError = String(err);
    var el = document.getElementById('app');
    if (el) { el.setAttribute('data-hydration', 'load-error'); }
    document.dispatchEvent(new CustomEvent('webui:client-error', { detail: String(err) }));
  });
})();
