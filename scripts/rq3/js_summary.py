#!/usr/bin/env python3
"""JS coverage of the SAF runs on a COMMON denominator.

branch-coverage.mjs reports percentages over the scripts a run happened to load, so runs that reach different scripts have
different denominators (e.g. pagekit: 8122 statements vs 1418). Here the universe of an app is, per script key, the largest
total seen in any run of that app (scripts a run never loaded count as 0 covered), so every run of an app is scored on
the same total. Per-script covered *sets* are not available, so only counts (no union/complementarity) can be computed.

    js_summary.py [--apps dimeshift pagekit phoenix petclinic] [--metric statements] [--csv out.csv]
Runs are the results/crawlbench/<app>_<saf>_<traversal>_<stamp>-<n>-branch.json files, grouped by app and SAF.
"""
import argparse, csv, glob, json, os, re, statistics as st

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
NAME = re.compile(r'(?P<app>\w+?)_(?P<saf>[a-z-]+?)_(?P<trav>[a-z_]+?)_(?P<stamp>\d{8}_\d{6})-\d+-branch\.json$')
METRICS = ('statements', 'branches', 'functions', 'lines')


PLATFORM_CUTOFF = '20261117_170000'   # Mac pilot runs are all earlier; the Ubuntu campaign started 2026-11-17 18:09


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apps', nargs='*', default=['dimeshift', 'pagekit', 'phoenix', 'petclinic'])
    ap.add_argument('--metric', default='statements', choices=METRICS)
    ap.add_argument('--csv')
    ap.add_argument('--platform', default='all', choices=['all', 'mac', 'linux'],
                    help='mac: runs before 20261117_170000, linux: runs from then on (the Ubuntu machine)')
    a = ap.parse_args()
    rows = []
    for app in a.apps:
        runs = []
        for p in sorted(glob.glob(os.path.join(ROOT, 'results', 'crawlbench', f'{app}_*-branch.json'))):
            m = NAME.search(os.path.basename(p))
            if not m or m['app'] != app:
                continue
            if (a.platform == 'mac' and m['stamp'] >= PLATFORM_CUTOFF) or (a.platform == 'linux' and m['stamp'] < PLATFORM_CUTOFF):
                continue
            d = json.load(open(p))
            runs.append((m['saf'], m['stamp'], d))
        if not runs:
            continue
        uni = {m: {} for m in METRICS}
        for _, _, d in runs:
            for k, v in d['perScript'].items():
                for m in METRICS:
                    uni[m][k] = max(uni[m].get(k, 0), v[m]['total'])
        total = {m: sum(uni[m].values()) for m in METRICS}
        print(f"\n=== {app}  ({a.metric}; common denominator {total[a.metric]}, {len(uni[a.metric])} scripts)")
        by = {}
        for saf, stamp, d in runs:
            cov = {m: sum(v[m]['covered'] for v in d['perScript'].values()) for m in METRICS}
            r = {'app': app, 'saf': saf, 'stamp': stamp, 'tests': len(d['perTest']), 'scripts': len(d['perScript'])}
            for m in METRICS:
                r[m + '_covered'] = cov[m]
                r[m + '_pct_common'] = round(100.0 * cov[m] / total[m], 2) if total[m] else 0.0
                r[m + '_pct_own'] = d['final']['percent'][m]
            rows.append(r)
            by.setdefault(saf, []).append(r)
        for saf, rs in sorted(by.items()):
            v = [r[a.metric + '_pct_common'] for r in rs]
            sd = f"{st.stdev(v):5.2f}" if len(v) > 1 else '  n/a'
            print(f"  {saf:9s} n={len(rs)}  common-denominator mean {st.mean(v):6.2f}  sd {sd}   "
                  f"own-denominator {[r[a.metric + '_pct_own'] for r in rs]}  tests {[r['tests'] for r in rs]}  covered {[r[a.metric + '_covered'] for r in rs]}")
    if a.csv and rows:
        with open(a.csv, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=list(rows[0].keys())); w.writeheader(); w.writerows(rows)
        print('\nWrote', a.csv)


if __name__ == '__main__':
    main()
