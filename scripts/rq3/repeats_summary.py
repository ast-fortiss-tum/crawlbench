#!/usr/bin/env python3
"""Run-to-run noise of the repeats study (logs/repeats_<app>.status written by scripts/crawl-bench/run_repeats.sh).

For every app x SAF cell: mean, sd, min-max over the repetitions of final line/block/edge coverage, requests and
crawl duration. Then, per app: is the SAF effect larger than the noise? (ranges overlap?, pairwise difference in sd
units, how often each SAF ranks first / last across repetitions.) Only runs with "END <run> ok" count.

    repeats_summary.py [--apps mantisbt mrbs ppma] [--metric lines] [--csv out.csv]
"""
import argparse
import csv
import itertools
import json
import os
import re
import statistics as st

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
RUN = re.compile(r'END (?P<run>(?P<app>\w+?)_(?P<saf>\w+?)_(?P<trav>\w+?)_(?P<min>\d+)m_rep(?P<rep>\d+)) ok coverage=(?P<cov>\S+)')


def load(app):
    rows = {}
    path = os.path.join(ROOT, 'logs', f'repeats_{app}.status')
    if not os.path.exists(path):
        return []
    for line in open(path):
        m = RUN.search(line)
        if not m:
            continue
        d = json.load(open(os.path.join(ROOT, m['cov'])))
        g = d['growth']
        rows[m['run']] = {  # a retried run overwrites its earlier (failed or stale) entry
            'app': m['app'], 'saf': m['saf'], 'rep': int(m['rep']), 'run': m['run'],
            'lines': d['final']['lines']['percent'], 'blocks': d['final']['blocks']['percent'],
            'edges': d['final']['edges']['percent'], 'lines_covered': d['final']['lines']['covered'],
            'requests': len(g), 'last_request_min': round(g[-1]['elapsed_s'] / 60, 1) if g else 0.0}
    return list(rows.values())


def sd(v):
    return st.stdev(v) if len(v) > 1 else float('nan')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--apps', nargs='*', default=['mantisbt', 'mrbs', 'ppma'])
    ap.add_argument('--metric', default='lines', choices=['lines', 'blocks', 'edges'])
    ap.add_argument('--csv')
    a = ap.parse_args()

    all_rows = []
    for app in a.apps:
        rows = load(app)
        all_rows += rows
        if not rows:
            print(f'{app}: no completed runs')
            continue
        safs = sorted({r['saf'] for r in rows})
        print(f"\n=== {app}  ({a.metric} coverage %, final cumulative, per repetition)")
        cell = {}
        for s in safs:
            rs = sorted((r for r in rows if r['saf'] == s), key=lambda r: r['rep'])
            v = [r[a.metric] for r in rs]
            cell[s] = {'rows': rs, 'v': v}
            print(f"  {s:8s} n={len(v)}  mean {st.mean(v):6.2f}  sd {sd(v):5.2f}  range {min(v):6.2f}-{max(v):6.2f}   "
                  f"reps {[round(x, 1) for x in v]}  requests {[r['requests'] for r in rs]}")
        within = [sd(c['v']) for c in cell.values() if len(c['v']) > 1]
        pooled = (sum(x * x for x in within) / len(within)) ** 0.5 if within else float('nan')
        print(f"  pooled within-SAF sd: {pooled:.2f} pp")
        for s1, s2 in itertools.combinations(safs, 2):
            m1, m2 = st.mean(cell[s1]['v']), st.mean(cell[s2]['v'])
            overlap = not (min(cell[s1]['v']) > max(cell[s2]['v']) or min(cell[s2]['v']) > max(cell[s1]['v']))
            z = (m1 - m2) / pooled if pooled and pooled == pooled else float('nan')
            print(f"  {s1} - {s2}: {m1 - m2:+6.2f} pp  = {z:+5.1f} pooled sd   ranges {'OVERLAP' if overlap else 'separate'}")
        # rank per repetition (only repetitions that have every SAF)
        reps = sorted({r['rep'] for r in rows})
        first, last, ranks = {s: 0 for s in safs}, {s: 0 for s in safs}, 0
        for rep in reps:
            at = {r['saf']: r[a.metric] for r in rows if r['rep'] == rep}
            if set(at) != set(safs):
                continue
            ranks += 1
            order = sorted(at, key=lambda k: -at[k])
            first[order[0]] += 1
            last[order[-1]] += 1
        if ranks:
            print(f"  rank per repetition ({ranks} complete): first {first}  last {last}")
        print(f"  requests per run: " + ', '.join(f"{s} {min(r['requests'] for r in c['rows'])}-{max(r['requests'] for r in c['rows'])}" for s, c in cell.items()))

    if a.csv:
        with open(a.csv, 'w', newline='') as f:
            w = csv.DictWriter(f, fieldnames=list(all_rows[0].keys()))
            w.writeheader()
            w.writerows(sorted(all_rows, key=lambda r: (r['app'], r['saf'], r['rep'])))
        print('\nWrote', a.csv)


if __name__ == '__main__':
    main()
