(function () {
  if (!window.WebUIClient) { return; }
  WebUIClient.boot({ wasmUrl: '/__assets/app.wasm', target: 'app' }).then(function (html) {
    document.dispatchEvent(new CustomEvent('webui:client-ready', { detail: { bytes: html.length } }));
  }).catch(function (err) {
    var el = document.getElementById('app');
    if (el) { el.setAttribute('data-hydration', 'load-error'); }
    document.dispatchEvent(new CustomEvent('webui:client-error', { detail: String(err) }));
  });
})();
