// Implicit oracle for translated DANTE suites (DANTE suites contain no assertions).
// Mode ORACLE_MODE=record: every check() writes its observation to golden-raw/; merge them with
//   python3 scripts/rq4/dante2pw.py merge <project>
// Otherwise check() compares the observation against golden.json and throws on a deviation.
//
// What is compared (all robust against run-to-run noise because golden.json is built from >= 3 baseline runs):
//   * URL (path + hash, digits masked), document title
//   * visible text lines (digits masked): every line seen in ALL baseline runs must be present,
//     every line present now must have been seen in SOME baseline run
//   * count of visible controls per tag (a, button, input, select, textarea)
//   * HTTP responses >= 400 and failed requests of type document/xhr/fetch (set must stay inside the baseline union)
//   * console errors and uncaught page errors (set must stay inside the baseline union)
import type { Page } from '@playwright/test';
import * as fs from 'fs';
import * as path from 'path';

const RECORD = process.env.ORACLE_MODE === 'record';
const GOLDEN_FILE = path.join(__dirname, 'golden.json');
const RAW_DIR = path.join(__dirname, 'golden-raw');

let golden: any = null;
function loadGolden(): any {
  if (golden) return golden;
  golden = JSON.parse(fs.readFileSync(GOLDEN_FILE, 'utf8'));
  return golden;
}

const mask = (s: string) => s.replace(/\s+/g, ' ').replace(/\d+/g, '#').trim().slice(0, 200);

type Obs = { loc: string; title: string; ctl: string; lines: string[] };

async function observe(page: Page): Promise<Obs> {
  await page.waitForLoadState('load', { timeout: 5000 }).catch(() => {});
  await page.waitForLoadState('networkidle', { timeout: 2000 }).catch(() => {});
  const raw = await page.evaluate(() => {
    const vis = (e: Element) => {
      const r = (e as HTMLElement).getBoundingClientRect();
      const st = getComputedStyle(e);
      return r.width > 0 && r.height > 0 && st.visibility !== 'hidden' && st.display !== 'none';
    };
    const counts: Record<string, number> = {};
    for (const e of Array.from(document.querySelectorAll('a,button,input,select,textarea'))) {
      if (!vis(e)) continue;
      const t = e.tagName.toLowerCase();
      counts[t] = (counts[t] || 0) + 1;
    }
    return {
      loc: location.pathname + location.hash,
      title: document.title,
      counts,
      text: document.body ? document.body.innerText : '',
    };
  });
  const lines = Array.from(new Set(raw.text.split('\n').map(mask).filter(Boolean))).sort();
  const ctl = ['a', 'button', 'input', 'select', 'textarea'].map((t) => `${t}:${raw.counts[t] || 0}`).join(',');
  return { loc: mask(raw.loc), title: mask(raw.title), ctl, lines };
}

export class Oracle {
  private net = new Set<string>();
  private cons = new Set<string>();
  private step = 0;
  private problems: string[] = [];
  constructor(private page: Page, private id: string) {
    page.on('response', (r) => {
      try {
        const t = r.request().resourceType();
        if (['document', 'xhr', 'fetch'].includes(t) && r.status() >= 400) {
          this.net.add(`${r.request().method()} ${mask(new URL(r.url()).pathname)} ${r.status()}`);
        }
      } catch {}
    });
    page.on('requestfailed', (rq) => {
      try {
        const t = rq.resourceType();
        const err = rq.failure()?.errorText || '';
        if (['document', 'xhr', 'fetch'].includes(t) && !/ERR_ABORTED/.test(err)) {
          this.net.add(`FAILED ${rq.method()} ${mask(new URL(rq.url()).pathname)}`);
        }
      } catch {}
    });
    page.on('console', (m) => {
      if (m.type() === 'error') this.cons.add(mask(m.text()));
    });
    page.on('pageerror', (e) => this.cons.add('PAGEERROR ' + mask(String(e.message || e))));
  }

  /** Observation point after an action. Throws (replay mode) when the observation deviates from the baseline. */
  async check(): Promise<void> {
    const key = `${this.id}|${this.step++}`;
    const obs = await observe(this.page);
    if (RECORD) {
      this.save(key, obs);
      return;
    }
    const g = loadGolden().obs[key];
    if (!g) {
      this.problems.push(`${key}: no baseline observation`);
    } else {
      if (!g.loc.includes(obs.loc)) this.problems.push(`${key}: url ${obs.loc}`);
      if (!g.title.includes(obs.title)) this.problems.push(`${key}: title ${obs.title}`);
      if (!g.ctl.includes(obs.ctl)) this.problems.push(`${key}: controls ${obs.ctl}`);
      const miss = g.required.filter((l: string) => !obs.lines.includes(l));
      const extra = obs.lines.filter((l: string) => !g.allowed.includes(l));
      if (miss.length) this.problems.push(`${key}: missing text ${JSON.stringify(miss.slice(0, 3))}`);
      if (extra.length) this.problems.push(`${key}: unexpected text ${JSON.stringify(extra.slice(0, 3))}`);
    }
    if (this.problems.length) throw new Error('oracle: ' + this.problems.join(' | '));
  }

  /** End of the test: network and console findings. */
  async finish(): Promise<void> {
    await this.check();
    const net = Array.from(this.net).sort();
    const cons = Array.from(this.cons).sort();
    if (RECORD) {
      this.save(`${this.id}|end`, { net, cons });
      return;
    }
    const g = loadGolden().end[`${this.id}|end`] || { net: [], cons: [] };
    const newNet = net.filter((x) => !g.net.includes(x));
    const newCons = cons.filter((x) => !g.cons.includes(x));
    if (newNet.length) throw new Error('oracle: new HTTP failures ' + JSON.stringify(newNet.slice(0, 3)));
    if (newCons.length) throw new Error('oracle: new console errors ' + JSON.stringify(newCons.slice(0, 3)));
  }

  private save(key: string, value: any) {
    fs.mkdirSync(RAW_DIR, { recursive: true });
    const f = path.join(RAW_DIR, `${key.replace(/[^\w.-]/g, '_')}.${process.pid}.${Date.now()}.json`);
    fs.writeFileSync(f, JSON.stringify({ key, value }));
  }
}
