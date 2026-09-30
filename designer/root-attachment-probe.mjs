// root-attachment probe: the numbers behind "should all the css hang off :root?".
//
// usage: node designer/root-attachment-probe.mjs <url>
// run it from a directory where `playwright` resolves (the repo root).
//
// measures, on a live page:
//   1. inherited custom properties — every element's computed style carries the
//      `:root` token set; this is the per-element cost of attaching them there
//   2. rule utilization — of the rules the sheet ships, how many can apply to
//      THIS page's class set at all (dead rules are bytes the page cannot use)
//   3. token utilization — declared on `:root` vs referenced by applicable rules
//   4. theme-flip cost — the engine's real mechanism (`data-theme` on
//      documentElement) vs the same declarations attached to a subtree
//   5. the override surface — specificity histogram + `!important` count, i.e.
//      how hard it is for a consumer's own css to win
//
// reads only: safe to run against any served page.
import { chromium } from 'playwright';

const [, , url] = process.argv;
if (!url) {
	console.error('usage: node designer/root-attachment-probe.mjs <url>');
	process.exit(2);
}

const browser = await chromium.launch();
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
await page.goto(url, { waitUntil: 'networkidle' });
await page.waitForTimeout(400);

const out = await page.evaluate(async () => {
	const els = [...document.querySelectorAll('*')];
	const doc = document.documentElement;

	// ---- 1. inherited custom properties per element
	const propCounts = els.map((el) => {
		const cs = getComputedStyle(el);
		let n = 0;
		for (const k of cs) if (k.startsWith('--')) n++;
		return n;
	}).sort((a, b) => a - b);
	const at = (q) => propCounts[Math.min(propCounts.length - 1, Math.floor(propCounts.length * q))] ?? 0;

	// ---- the page's own class vocabulary
	const pageClasses = new Set();
	for (const el of els) for (const c of el.classList) pageClasses.add(c);

	// ---- 2./3./5. walk the CSSOM
	let total = 0, noClass = 0, applicable = 0, dead = 0, partial = 0;
	let bytesAll = 0, bytesApplicable = 0, important = 0;
	const spec = { singleClass: 0, multiClass: 0, id: 0, elementOnly: 0 };
	const declaredTokens = new Set();
	const usedTokens = new Set();
	const ruleTexts = [];

	const countClasses = (sel) => (sel.match(/\.[A-Za-z0-9_-]+/g) || []).map((s) => s.slice(1));
	const specOf = (sel) => {
		const ids = (sel.match(/#[A-Za-z0-9_-]+/g) || []).length;
		const cl = countClasses(sel).length + (sel.match(/\[[^\]]+\]/g) || []).length
			+ (sel.match(/:(?!:)[a-z-]+/g) || []).length;
		const el = (sel.replace(/[#.\[][^\s>+~,]*/g, '').match(/[a-zA-Z][a-zA-Z0-9-]*/g) || []).length
			+ (sel.match(/::[a-z-]+/g) || []).length;
		return { ids, cl, el };
	};

	const walk = (rules) => {
		for (const rule of rules) {
			if (rule.cssRules) { walk(rule.cssRules); continue; }
			if (!rule.selectorText) continue;
			total++;
			const text = rule.cssText;
			bytesAll += text.length;
			if (text.includes('!important')) important++;
			const inRoot = /:root/.test(rule.selectorText);
			if (inRoot && rule.style) {
				for (let i = 0; i < rule.style.length; i++) {
					const p = rule.style[i];
					if (p.startsWith('--')) declaredTokens.add(p);
				}
			}
			const classes = countClasses(rule.selectorText);
			const s = specOf(rule.selectorText);
			if (s.ids > 0) spec.id++;
			else if (s.cl >= 2) spec.multiClass++;
			else if (s.cl === 1) spec.singleClass++;
			else spec.elementOnly++;
			if (classes.length === 0) { noClass++; bytesApplicable += text.length; continue; }
			const present = classes.filter((c) => pageClasses.has(c)).length;
			if (present === classes.length) { applicable++; bytesApplicable += text.length; }
			else if (present === 0) dead++;
			else partial++;
			if (present > 0) {
				const refs = text.match(/var\(--[A-Za-z0-9_-]+/g) || [];
				for (const r of refs) usedTokens.add(r.slice(6));
			}
		}
	};
	const diagnostics = [];
	for (const sheet of document.styleSheets) {
		try { walk(sheet.cssRules); } catch (e) { diagnostics.push(`${sheet.href || '(inline)'}: ${e.name}: ${e.message}`); }
	}
	const inlineStyleTags = document.querySelectorAll('style').length;
	const linkTags = [...document.querySelectorAll('link[rel="stylesheet"]')].map((l) => l.href);
	const sheetCount = document.styleSheets.length;
	// fallback: parse the served css text when the CSSOM is unavailable
	let textRules = null;
	if (total === 0 && linkTags.length) {
		const cssText = await (await fetch(linkTags[0])).text();
		// brace-aware scan (one nesting level is enough for @media/@layer blocks)
		const scan = [];
		let depth = 0, start = 0;
		for (let i = 0; i < cssText.length; i++) {
			const c = cssText[i];
			if (c === '{') {
				if (depth === 0) { const sel = cssText.slice(start, i).trim(); scan.push({ sel, open: i }); }
				depth++;
			} else if (c === '}') {
				depth--;
				if (depth === 0) { const top = scan[scan.length - 1]; if (top && top.open !== undefined) { top.text = cssText.slice(top.open + 1, i); top.end = i; } }
				if (depth === 0) start = i + 1;
			}
		}
		let deadText = 0, applicableText = 0, partialText = 0, noClassText = 0;
		let deadBytes = 0, applicableBytes = 0;
		const textSpec = { singleClass: 0, multiClass: 0, id: 0, elementOnly: 0 };
		let textImportant = 0;
		const refsOfApplicable = new Set();
		const declaredFromText = new Set();
		for (const block of scan) {
			const sel = block.sel;
			if (/^@/.test(sel)) { applicableText++; continue; } // at-rule wrapper: count its inner rules only
			const body = block.text || '';
			if (body.includes('!important')) textImportant++;
			if (/:root/.test(sel)) {
				for (const d of body.match(/--[A-Za-z0-9_-]+\s*:/g) || []) declaredFromText.add(d.replace(/\s*:$/, ''));
			}
			const s = specOf(sel);
			if (s.ids > 0) textSpec.id++;
			else if (s.cl >= 2) textSpec.multiClass++;
			else if (s.cl === 1) textSpec.singleClass++;
			else textSpec.elementOnly++;
			const classes = countClasses(sel);
			if (classes.length === 0) { noClassText++; continue; }
			const present = classes.filter((c) => pageClasses.has(c)).length;
			const bytes = body.length;
			if (present === classes.length) {
				applicableText++; applicableBytes += bytes;
				for (const r of body.match(/var\(--[A-Za-z0-9_-]+/g) || []) refsOfApplicable.add(r.slice(6));
			} else if (present === 0) { deadText++; deadBytes += bytes; }
			else partialText++;
		}
		textRules = {
			topLevelBlocks: scan.length, rulesFromText: noClassText + applicableText + deadText + partialText,
			noClassText, applicableText, deadText, partialText,
			bytesAllText: cssText.length, applicableBytes, deadBytes,
			deadByteFraction: +((deadBytes / cssText.length) || 0).toFixed(3),
			spec: textSpec, important: textImportant,
			tokensDeclared: declaredFromText.size, tokensReferencedByApplicable: refsOfApplicable.size,
		};
	}

	// ---- 4. theme-flip cost: :root vs a subtree carrying the same declarations
	const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[s.length >> 1]; };
	const flip = (flipFn, readFn, n = 40) => {
		const times = [];
		readFn(); // warm
		for (let i = 0; i < n; i++) {
			const t0 = performance.now();
			flipFn(i % 2 === 0);
			readFn();
			times.push(performance.now() - t0);
		}
		return { medianMs: +median(times).toFixed(3), maxMs: +Math.max(...times).toFixed(3) };
	};

	const rootFlip = flip(
		(dark) => doc.setAttribute('data-theme', dark ? 'dark' : 'light'),
		() => { void getComputedStyle(document.body).color; void document.body.offsetHeight; },
	);

	// the synthetic subtree: the sheet's own dark declarations, re-scoped.
	let scopeFlip = null, scopeElements = 0;
	const scopeEl = document.querySelector('main') || document.body;
	if (scopeEl) {
		// take the sheet text, lift every `:root[data-theme="dark"]{...}` block to the scope
		let cssText = '';
		for (const sheet of document.styleSheets) {
			try {
				for (const rule of sheet.cssRules) if (rule.cssText.includes('data-theme')) cssText += rule.cssText + '\n';
			} catch { /* ignore */ }
		}
		const lifted = cssText
			.replace(/:root\[data-theme="dark"\]\s*\{/g, '.probe-scope[data-probe="dark"] {')
			.replace(/:root\[data-theme="[^"]*"\]\s*\{/g, '.probe-scope {')
			.replace(/:root\s*\{/g, '.probe-scope, :root {');
		const style = document.createElement('style');
		style.textContent = lifted;
		document.head.appendChild(style);
		scopeEl.classList.add('probe-scope');
		scopeElements = scopeEl.querySelectorAll('*').length;
		scopeFlip = flip(
			(dark) => scopeEl.setAttribute('data-probe', dark ? 'dark' : 'light'),
			() => { void getComputedStyle(scopeEl).color; void scopeEl.offsetHeight; },
		);
		style.remove();
		scopeEl.classList.remove('probe-scope');
		doc.removeAttribute('data-theme');
	}

	// ---- bytes actually transferred for the stylesheet(s)
	let sheetTransfer = 0, sheetDecoded = 0;
	for (const e of performance.getEntriesByType('resource')) {
		if ((e.name || '').includes('css')) {
			sheetTransfer += e.transferSize || 0;
			sheetDecoded += e.decodedBodySize || 0;
		}
	}

	return {
		domNodes: els.length,
		customProperties: {
			min: propCounts[0] ?? 0, median: at(0.5), p90: at(0.9), max: propCounts[propCounts.length - 1] ?? 0,
			inheritedInstances: propCounts.reduce((a, b) => a + b, 0),
		},
		pageClasses: pageClasses.size,
		rules: { total, noClass, applicable, dead, partial, bytesAll, bytesApplicable, deadFraction: total ? +((dead / total)).toFixed(3) : 0 },
		tokens: { declared: declaredTokens.size, referencedByApplicable: usedTokens.size },
		overrideSurface: { ...spec, important },
		themeFlip: { root: rootFlip, subtree: scopeFlip, scopeElements },
		stylesheet: { transferBytes: sheetTransfer, decodedBytes: sheetDecoded },
		cssom: { sheetCount, inlineStyleTags, linkTags, diagnostics, textRules },
	};
});

console.log(JSON.stringify(out, null, 2));
await browser.close();