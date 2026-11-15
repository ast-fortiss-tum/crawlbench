#!/usr/bin/env node
// Istanbul-style statement / branch / function / line coverage from the raw V8 block coverage that
// DANTE's CodeCoverage.java dumps into <test-suite>/coverage-reports/v8-raw/ (see README.md).
//
// Usage: node branch-coverage.mjs <v8-raw-dir> [--json out.json] [--detail]
//
// How it works: the app's JavaScript is parsed with acorn to enumerate statements, functions and branch
// arms (if/else arms, ternary arms, switch cases, every operand of && / || / ??). V8's block coverage says
// which source ranges ran; an item counts as covered when the innermost V8 range containing its start
// offset has count > 0. Coverage is computed per test (partial coverage of one test case) and cumulatively
// over the tests in execution order. Items outside the script's `lineRanges` (library code in bundles) are
// ignored, mirroring DANTE's own byte coverage.
//
// Caveat: an `if` without `else` contributes only its explicit arm (V8 has no range for the implicit
// else), so branch totals are slightly lower than Istanbul's.
import fs from 'node:fs';
import path from 'node:path';
import * as acorn from 'acorn';
import * as walk from 'acorn-walk';

const args = process.argv.slice(2);
const rawDir = args.find((a) => !a.startsWith('--') && args[args.indexOf(a) - 1] !== '--json');
const jsonOut = args.includes('--json') ? args[args.indexOf('--json') + 1] : null;
const detail = args.includes('--detail');
if (!rawDir) {
  console.error('Usage: node branch-coverage.mjs <v8-raw-dir> [--json out.json] [--detail]');
  process.exit(1);
}

const readJson = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const KINDS = ['statements', 'branches', 'functions', 'lines'];

function parse(src) {
  const base = { ecmaVersion: 'latest', allowHashBang: true, allowReturnOutsideFunction: true, allowAwaitOutsideFunction: true };
  try { return acorn.parse(src, { ...base, sourceType: 'script' }); } catch { /* try as module */ }
  return acorn.parse(src, { ...base, sourceType: 'module' });
}

// Enumerate coverable items. Each item: { kind, pos, line }
function enumerateItems(src, lineRanges) {
  const lineStarts = [0];
  for (let i = 0; i < src.length; i++) if (src.charCodeAt(i) === 10) lineStarts.push(i + 1);
  const lineOf = (pos) => {
    let lo = 0, hi = lineStarts.length - 1;
    while (lo < hi) { const mid = (lo + hi + 1) >> 1; if (lineStarts[mid] <= pos) lo = mid; else hi = mid - 1; }
    return lo + 1; // 1-based, like lineRanges
  };
  const inScope = (line) => lineRanges.length === 0 || lineRanges.some(([s, e]) => line >= s && line <= e);

  const items = [];
  const add = (kind, pos) => { const line = lineOf(pos); if (inScope(line)) items.push({ kind, pos, line }); };

  const ast = parse(src);
  const stmt = (node) => add('statements', node.start);
  const fn = (node) => { add('functions', node.body.start); if (node.expression) add('statements', node.body.start); };
  const handlers = {};
  for (const t of ['ExpressionStatement', 'VariableDeclaration', 'ReturnStatement', 'IfStatement', 'ForStatement',
    'ForInStatement', 'ForOfStatement', 'WhileStatement', 'DoWhileStatement', 'ThrowStatement', 'TryStatement',
    'SwitchStatement', 'BreakStatement', 'ContinueStatement', 'DebuggerStatement', 'WithStatement', 'ClassDeclaration']) {
    handlers[t] = stmt;
  }
  for (const t of ['FunctionDeclaration', 'FunctionExpression', 'ArrowFunctionExpression']) handlers[t] = fn;
  handlers.IfStatement = (node) => {
    stmt(node);
    add('branches', node.consequent.start);
    if (node.alternate) add('branches', node.alternate.start);
  };
  handlers.ConditionalExpression = (node) => { add('branches', node.consequent.start); add('branches', node.alternate.start); };
  handlers.SwitchStatement = (node) => {
    stmt(node);
    for (const c of node.cases) if (c.consequent.length) add('branches', c.consequent[0].start);
  };
  const seenLogical = new Set();
  handlers.LogicalExpression = (node) => {
    if (seenLogical.has(node)) return;
    const operands = [];
    const flatten = (n) => {
      if (n.type === 'LogicalExpression' && n.operator === node.operator) { seenLogical.add(n); flatten(n.left); flatten(n.right); }
      else operands.push(n);
    };
    flatten(node);
    for (const o of operands) add('branches', o.start);
  };
  walk.full(ast, (node) => { if (handlers[node.type]) handlers[node.type](node); });
  return items;
}

// Annotate each item with the V8 count of its innermost containing range.
function countsFor(items, ranges) {
  // ranges: [start, end, count]; nested-or-disjoint. Sweep in position order with a stack.
  const rs = ranges.slice().sort((a, b) => a[0] - b[0] || b[1] - a[1]);
  const order = items.map((_, i) => i).sort((a, b) => items[a].pos - items[b].pos);
  const counts = new Array(items.length).fill(0);
  const stack = [];
  let ri = 0;
  for (const idx of order) {
    const pos = items[idx].pos;
    while (ri < rs.length && rs[ri][0] <= pos) { stack.push(rs[ri]); ri++; }
    while (stack.length && stack[stack.length - 1][1] <= pos) stack.pop();
    counts[idx] = stack.length ? stack[stack.length - 1][2] : 0;
  }
  return counts;
}

// ---- load dump ------------------------------------------------------------------------------------------
const scriptsDir = path.join(rawDir, 'scripts');
const testsDir = path.join(rawDir, 'tests');
const scripts = {};
for (const f of fs.readdirSync(scriptsDir).filter((n) => n.endsWith('.json'))) {
  const key = f.slice(0, -5);
  const meta = readJson(path.join(scriptsDir, f));
  const src = fs.readFileSync(path.join(scriptsDir, key + '.js'), 'utf8');
  try {
    scripts[key] = { url: meta.url, items: enumerateItems(src, meta.lineRanges || []) };
  } catch (e) {
    console.error(`[skip] cannot parse ${meta.url}: ${e.message}`);
  }
}
const orderFile = path.join(rawDir, 'tests.txt');
const testNames = fs.existsSync(orderFile)
  ? fs.readFileSync(orderFile, 'utf8').split('\n').map((s) => s.trim()).filter(Boolean)
  : fs.readdirSync(testsDir).sort();

// ---- per-test and cumulative coverage ---------------------------------------------------------------------
const cumCovered = {}; // key -> Set(item index)
for (const k of Object.keys(scripts)) cumCovered[k] = new Set();
const lineKey = (it) => it.line;

function summarise(coveredByScript) {
  const totals = Object.fromEntries(KINDS.map((k) => [k, { covered: 0, total: 0 }]));
  const perScript = {};
  for (const [key, s] of Object.entries(scripts)) {
    const cov = coveredByScript[key] || new Set();
    const t = Object.fromEntries(KINDS.map((k) => [k, { covered: 0, total: 0 }]));
    const lines = new Map(); // line -> covered?
    s.items.forEach((it, i) => {
      if (it.kind === 'statements') { const l = lineKey(it); lines.set(l, lines.get(l) || cov.has(i)); }
      t[it.kind].total++;
      if (cov.has(i)) t[it.kind].covered++;
    });
    t.lines.total = lines.size;
    t.lines.covered = [...lines.values()].filter(Boolean).length;
    perScript[key] = t;
    for (const k of KINDS) { totals[k].covered += t[k].covered; totals[k].total += t[k].total; }
  }
  const pct = (c) => (c.total ? (100 * c.covered) / c.total : 0);
  const out = { totals, percent: Object.fromEntries(KINDS.map((k) => [k, +pct(totals[k]).toFixed(2)])) };
  // unweighted mean over scripts, comparable to DANTE's "summary" line
  const keys = Object.keys(perScript);
  out.meanOverScripts = Object.fromEntries(KINDS.map((k) => [k,
    +(keys.reduce((a, key) => a + pct(perScript[key][k]), 0) / Math.max(keys.length, 1)).toFixed(2)]));
  return { summary: out, perScript };
}

const perTest = [];
for (const test of testNames) {
  const dir = path.join(testsDir, test);
  if (!fs.existsSync(dir)) continue;
  const testCovered = {};
  for (const f of fs.readdirSync(dir).filter((n) => n.endsWith('.json'))) {
    const key = f.slice(0, -5);
    const s = scripts[key];
    if (!s) continue;
    const dump = readJson(path.join(dir, f));
    const ranges = dump.functions.flatMap((fnc) => fnc.ranges);
    const counts = countsFor(s.items, ranges);
    const set = new Set();
    counts.forEach((c, i) => { if (c > 0) set.add(i); });
    testCovered[key] = set;
    for (const i of set) cumCovered[key].add(i);
  }
  const own = summarise(testCovered).summary;
  const cum = summarise(cumCovered).summary;
  const row = { test, own: own.percent, cumulative: cum.percent };
  if (detail) row.coveredItems = Object.fromEntries(Object.entries(testCovered).map(([k, v]) => [k, [...v]]));
  perTest.push(row);
}

const final = summarise(cumCovered);
console.log(`Scripts analysed: ${Object.keys(scripts).length}, tests: ${perTest.length}`);
console.log('\nCumulative coverage over the test suite (Istanbul-style, from V8 block coverage):');
for (const k of KINDS) {
  const t = final.summary.totals[k];
  console.log(`  ${k.padEnd(11)} ${String(t.covered).padStart(6)} / ${String(t.total).padEnd(6)} ${final.summary.percent[k].toFixed(2)}%   (mean over scripts ${final.summary.meanOverScripts[k]}%)`);
}
console.log('\nPer script (statements / branches / functions / lines):');
for (const [key, t] of Object.entries(final.perScript)) {
  const f = (k) => `${t[k].covered}/${t[k].total}`;
  console.log(`  ${scripts[key].url}\n     ${f('statements')}  ${f('branches')}  ${f('functions')}  ${f('lines')}`);
}
if (perTest.length) {
  console.log('\nCumulative branch coverage growth by test (first 5, last 5):');
  const show = perTest.length > 10 ? [...perTest.slice(0, 5), null, ...perTest.slice(-5)] : perTest;
  for (const r of show) console.log(r ? `  ${r.test.padEnd(28)} own ${String(r.own.branches).padStart(6)}%  cumulative ${r.cumulative.branches}%` : '  ...');
}
if (jsonOut) {
  fs.writeFileSync(jsonOut, JSON.stringify({ final: final.summary, perScript: final.perScript, perTest }, null, 1));
  console.log(`\nWrote ${jsonOut}`);
}
