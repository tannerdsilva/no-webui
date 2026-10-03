// preview screenshots: full-page captures of the compiled previews, light + dark.
// usage: node designer/capture-previews.mjs [--width 1440]
//
// two things a file:// load cannot do for itself, handled here:
//
// 1. the compiled showcase links its sheet at the *content-addressed server
//    path* (`/__assets/css.<hash>`), which resolves to nothing on the local
//    filesystem — so the source sheet is injected and the capture shows the
//    styled page instead of an unstyled dump.
// 2. Chromium refuses a capture past ~16384 device px on either axis, and the
//    showcase page is taller than that — the capture scale is reduced to fit
//    one file per page+theme, and the chosen scale is reported.
import { chromium } from 'playwright';
import { mkdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const outDir = path.join(root, 'designer/previews/screenshots');
const cssFile = path.join(root, 'designer/assets/design-system.css');
const args = process.argv.slice(2);
let width = 1440;
const wi = args.indexOf('--width');
if (wi !== -1 && wi + 1 < args.length) width = parseInt(args[wi + 1], 10);

const DEVICE_PX_LIMIT = 16000;
const targets = [
  { name: 'showcase', file: 'designer/previews/showcase.html' },
  { name: 'design-system', file: 'designer/previews/designer-preview.html' },
];

mkdirSync(outDir, { recursive: true });
const css = readFileSync(cssFile, 'utf8');
const browser = await chromium.launch();
const results = [];

async function load(t, scheme, deviceScaleFactor) {
  const context = await browser.newContext({
    viewport: { width, height: 900 },
    deviceScaleFactor,
    colorScheme: scheme,
  });
  const page = await context.newPage();
  await page.goto('file://' + path.join(root, t.file), { waitUntil: 'networkidle' });
  await page.addStyleTag({ content: css });
  await page.waitForTimeout(400);
  return { context, page };
}

for (const t of targets) {
  for (const scheme of ['light', 'dark']) {
    // measure first: the page height is css px, independent of capture scale
    let { context, page } = await load(t, scheme, 2);
    const size = await page.evaluate(() => ({
      h: document.documentElement.scrollHeight,
      bg: getComputedStyle(document.body).backgroundColor,
    }));
    const dsf = Math.min(2, DEVICE_PX_LIMIT / size.h);
    const scaled = dsf < 2;
    if (scaled) {
      await context.close();
      ({ context, page } = await load(t, scheme, dsf));
    }
    const out = path.join(outDir, `${t.name}-${scheme}.png`);
    await page.screenshot({ path: out, fullPage: true });
    const devicePx = `${Math.round(width * dsf)}x${Math.round(size.h * dsf)} px`;
    console.log(
      `${path.basename(out)}  ${width}x${size.h} css px  ->  ${devicePx}` +
        (scaled ? `  (scaled to ${(dsf / 2).toFixed(2)} to fit the capture limit)` : '')
    );
    results.push({
      target: t.name,
      scheme,
      file: path.basename(out),
      height: size.h,
      deviceScaleFactor: dsf,
      bg: size.bg,
    });
    await context.close();
  }
}

await browser.close();
console.log(JSON.stringify(results, null, 2));