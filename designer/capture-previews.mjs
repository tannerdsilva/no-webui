// full-page showcase previews in light + dark mode.
// usage: node designer/capture-previews.mjs [--width 1440]
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '..');
const outDir = path.join(root, 'designer/previews/screenshots');
const args = process.argv.slice(2);
let width = 1440;
const wi = args.indexOf('--width');
if (wi !== -1 && wi + 1 < args.length) width = parseInt(args[wi + 1], 10);

const targets = [
  { name: 'showcase', file: 'designer/previews/showcase.html' },
  { name: 'design-system', file: 'designer/previews/designer-preview.html' },
];

mkdirSync(outDir, { recursive: true });

const browser = await chromium.launch();
const results = [];

for (const t of targets) {
  for (const scheme of ['light', 'dark']) {
    const context = await browser.newContext({
      viewport: { width, height: 900 },
      deviceScaleFactor: 2,
      colorScheme: scheme,
    });
    const page = await context.newPage();
    const url = 'file://' + path.join(root, t.file);
    await page.goto(url, { waitUntil: 'networkidle' });
    await page.waitForTimeout(400);
    const out = path.join(outDir, `${t.name}-${scheme}.png`);
    await page.screenshot({ path: out, fullPage: true });
    const size = await page.evaluate(() => ({
      h: document.documentElement.scrollHeight,
      bg: getComputedStyle(document.body).backgroundColor,
    }));
    results.push({ target: t.name, scheme, file: out, height: size.h, bg: size.bg });
    await context.close();
  }
}

await browser.close();
console.log(JSON.stringify(results, null, 2));
