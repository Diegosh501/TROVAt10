// Checks inline interaction handlers and local links in the single-page app.
// Run with: node tests/interactions-smoke.cjs
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const assert = require('node:assert/strict');

const root = path.join(__dirname, '..');
const html = fs.readFileSync(path.join(root, 'index.html'), 'utf8');
const script = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map(m => m[1]).join('\n');
new vm.Script(script, { filename: 'index.html:inline-script' });

const defined = new Set([
  ...[...script.matchAll(/(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\(/g)].map(m => m[1]),
  ...[...script.matchAll(/window\.([A-Za-z_$][\w$]*)\s*=/g)].map(m => m[1]),
]);
const browserBuiltins = new Set([
  'alert', 'confirm', 'prompt', 'open', 'close', 'focus', 'scrollTo',
  'setTimeout', 'clearTimeout', 'requestAnimationFrame', 'URL', 'Date',
  'encodeURIComponent', 'decodeURIComponent', 'parseInt', 'parseFloat',
]);
const onclickAttributes = [...html.matchAll(/onclick\s*=\s*(?:"([^"]*)"|'([^']*)')/g)];
const referenced = new Set();
for (const match of onclickAttributes) {
  const expression = match[1] ?? match[2] ?? '';
  for (const call of expression.matchAll(/(?<![.\w$])([A-Za-z_$][\w$]*)\s*\(/g)) {
    const name = call[1];
    if (!browserBuiltins.has(name)) referenced.add(name);
  }
}
const missing = [...referenced].filter(name => !defined.has(name));
assert.deepEqual(missing, [], `onclick handlers without app functions: ${missing.join(', ')}`);
assert.ok(onclickAttributes.length >= 80, `expected broad button coverage, found ${onclickAttributes.length} inline handlers`);

const localTargets = new Set();
for (const match of html.matchAll(/href\s*=\s*(?:"([^"]*)"|'([^']*)')/g)) {
  const href = match[1] ?? match[2] ?? '';
  if (!href || href.startsWith('#') || href.startsWith('${') || /^(?:https?:|mailto:|tel:|data:|javascript:)/i.test(href)) continue;
  const target = decodeURIComponent(href.split(/[?#]/, 1)[0]);
  if (target) localTargets.add(target);
}
const missingTargets = [...localTargets].filter(target => !fs.existsSync(path.join(root, target)));
assert.deepEqual(missingTargets, [], `local links with no target file: ${missingTargets.join(', ')}`);

console.log(`PASS: ${onclickAttributes.length} inline handlers resolve to app functions; ${localTargets.size} local links resolve to files.`);
