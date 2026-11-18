#!/usr/bin/env python3
"""Translate a DANTE selenium-actions-*.txt file into a Playwright project that MultilayerMT can mutate.

  dante2pw.py generate <actions.txt> <out_project_dir> --app dimeshift [--sleep-scale 1.0]
  dante2pw.py merge <out_project_dir>        # builds tests/golden.json from tests/golden-raw/*.json (>= 3 baseline runs)

One spec file per crawl path (paths are separated by a line '----'). Every action is followed by an
observation point of the implicit oracle in templates/oracle.ts.
Statement forms supported (the complete grammar of DANTE action files):
  driver.get("u"); Thread.sleep(n); driver.findElement(By.{xpath|id|name}("x")).{click|clear|sendKeys("t")}();
Anything else (switchTo().window, close, stray log lines) is reported and skipped.
"""
import argparse
import json
import re
import shutil
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
SEP = '----'

RE_GET = re.compile(r'^driver\.get\("(.*)"\);$')
RE_SLEEP = re.compile(r'^Thread\.sleep\((\d+)\);$')
RE_ACT = re.compile(r'^driver\.findElement\(By\.(xpath|id|name)\("(.*?)"\)\)\.(click|clear|sendKeys)\((?:"(.*)")?\);$')


def js(s: str) -> str:
    return json.dumps(s)


def locator(kind: str, val: str) -> str:
    if kind == 'xpath':
        sel = 'xpath=' + val
    elif kind == 'id':
        sel = f'[id="{val}"]'
    else:
        sel = f'[name="{val}"]'
    return f'page.locator({js(sel)}).first()'


def split_paths(text: str):
    paths, cur = [], []
    for line in text.splitlines():
        if line.strip() == SEP:
            if cur:
                paths.append(cur)
            cur = []
        else:
            cur.append(line.strip())
    # a trailing chunk without separator is an unfinished path (crawl stopped): DANTE ignores it, so do we
    return paths


def translate_path(lines, idx, scale, skipped):
    """Sleeps stay where they are; the observation point goes after the sleeps that follow a get/click."""
    body = []
    dirty = False  # a get/click happened and has not been observed yet

    def flush():
        nonlocal dirty
        if dirty:
            body.append('  await oracle.check();')
            dirty = False

    for ln in lines:
        if not ln:
            continue
        m = RE_SLEEP.match(ln)
        if m:
            body.append(f'  await page.waitForTimeout({int(float(m.group(1)) * scale)});')
            continue
        m = RE_GET.match(ln)
        if m:
            flush()
            body.append(f'  await page.goto({js(m.group(1))});')
            dirty = True
            continue
        m = RE_ACT.match(ln)
        if m:
            flush()
            kind, val, act, arg = m.groups()
            loc = locator(kind, val)
            if act == 'click':
                body.append(f'  await {loc}.click();')
                dirty = True
            elif act == 'clear':
                body.append(f'  await {loc}.fill("");')
            else:
                body.append(f'  await {loc}.pressSequentially({js(arg or "")});')
            continue
        skipped[ln[:60]] += 1
    flush()
    return body


def generate(args):
    text = Path(args.actions).read_text(errors='replace')
    out = Path(args.out)
    tests = out / 'tests'
    tests.mkdir(parents=True, exist_ok=True)
    shutil.copy(HERE / 'templates' / 'oracle.ts', tests / 'oracle.ts')
    skipped = defaultdict(int)
    paths = split_paths(text)
    for i, p in enumerate(paths):
        body = translate_path(p, i, args.sleep_scale, skipped)
        spec = ["import { test } from '@playwright/test';",
                "import { Oracle } from './oracle';", '',
                f"test('path{i:02d}', async ({{ page }}) => {{",
                f"  const oracle = new Oracle(page, 'path{i:02d}');"]
        spec += body
        spec += ['  await oracle.finish();', '});', '']
        (tests / f'path{i:02d}.spec.ts').write_text('\n'.join(spec))
    (out / 'playwright.config.ts').write_text(f"""import {{ defineConfig }} from '@playwright/test';

export default defineConfig({{
  testDir: './tests',
  timeout: 180_000,
  expect: {{ timeout: 5_000 }},
  fullyParallel: false,
  workers: 1,
  retries: 0,
  use: {{ viewport: {{ width: 1200, height: 890 }}, actionTimeout: 5_000, navigationTimeout: 30_000 }},
}});
""")
    cfg = {
        "app": args.app,
        "projectRoot": ".",
        "playwrightConfig": "playwright.config.ts",
        "testDir": "tests",
        "maxPwe": 8,
        "workers": 1,
        "layers": ["dom", "network"],
        "operatorSet": "thesis",
        "pageKeyQuery": "none",
        "network": {"resourceTypes": ["xhr", "fetch", "document"]},
        "testSelection": "covering",
        "mutantTimeoutMs": 600000,
        "reporters": ["json", "console"],
    }
    (out / 'mlmt.config.json').write_text(json.dumps(cfg, indent=2) + '\n')
    print(f'{len(paths)} paths -> {out}')
    for k, v in skipped.items():
        print(f'  skipped x{v}: {k}')


def merge(args):
    out = Path(args.out) / 'tests'
    raw = out / 'golden-raw'
    obs, end = defaultdict(list), defaultdict(list)
    for f in sorted(raw.glob('*.json')):
        d = json.loads(f.read_text())
        (end if d['key'].endswith('|end') else obs)[d['key']].append(d['value'])
    g = {'obs': {}, 'end': {}}
    for k, runs in obs.items():
        sets = [set(r['lines']) for r in runs]
        g['obs'][k] = {
            'runs': len(runs),
            'loc': sorted({r['loc'] for r in runs}),
            'title': sorted({r['title'] for r in runs}),
            'ctl': sorted({r['ctl'] for r in runs}),
            'required': sorted(set.intersection(*sets)),
            'allowed': sorted(set.union(*sets)),
        }
    for k, runs in end.items():
        g['end'][k] = {'net': sorted({x for r in runs for x in r['net']}),
                       'cons': sorted({x for r in runs for x in r['cons']})}
    (out / 'golden.json').write_text(json.dumps(g, indent=1))
    nruns = min((v['runs'] for v in g['obs'].values()), default=0)
    unstable = sum(1 for v in g['obs'].values() if len(v['allowed']) != len(v['required']))
    print(f"golden.json: {len(g['obs'])} observation points, min {nruns} runs, {unstable} with run-to-run text noise")


def main():
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest='cmd', required=True)
    g = sub.add_parser('generate')
    g.add_argument('actions')
    g.add_argument('out')
    g.add_argument('--app', required=True)
    g.add_argument('--sleep-scale', type=float, default=1.0)
    g.set_defaults(fn=generate)
    m = sub.add_parser('merge')
    m.add_argument('out')
    m.set_defaults(fn=merge)
    a = ap.parse_args()
    a.fn(a)


if __name__ == '__main__':
    sys.exit(main())
