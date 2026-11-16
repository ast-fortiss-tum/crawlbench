#!/usr/bin/env python3
"""Merge the per-request Xdebug coverage files written by branch_coverage_prepend.php.

Usage: merge_xdebug_coverage.py <coverage_data/requests dir> [--json out.json] [--exclude SUBSTR ...]
                                [--t0 EPOCH_SECONDS] [--checkpoints MIN [MIN ...]]

Reports, over all requests (cumulative) and as growth per request:
  lines          executed / executable lines (dead code excluded)
  blocks         executed basic blocks (what PHPUnit's php-code-coverage calls "branches")
  edges          taken outgoing edges of decision blocks (>= 2 successors): Istanbul-style branch coverage
  paths          executed / enumerated paths (Xdebug caps the enumeration for very branchy functions)
Only files that were loaded in at least one request appear in the totals.
"""
import argparse
import glob
import gzip
import json
import os
import sys


def items(x):
    """PHP's json_encode turns sequential arrays into lists and the rest into objects."""
    return x.items() if isinstance(x, dict) else enumerate(x)


class Merged:
    def __init__(self):
        self.lines = {}    # (file, line) -> bool executed (executable lines only)
        self.blocks = {}   # (file, func, op_start) -> bool hit
        self.edges = {}    # (file, func, op_start, target) -> bool taken, decision blocks only
        self.paths = {}    # (file, func, path tuple) -> bool hit

    def add(self, files):
        for f, info in files.items():
            for line, st in items(info.get('lines', {})):
                if st in (1, -1):
                    k = (f, int(line))
                    self.lines[k] = self.lines.get(k, False) or st == 1
            for fn, fdata in items(info.get('functions', {})):
                for _, b in items(fdata.get('branches', {})):
                    bk = (f, fn, b['op_start'])
                    self.blocks[bk] = self.blocks.get(bk, False) or bool(b['hit'])
                    if len(b['out']) >= 2:
                        for tgt, hit in zip(b['out'], b['out_hit']):
                            ek = bk + (tgt,)
                            self.edges[ek] = self.edges.get(ek, False) or bool(hit)
                for p in fdata.get('paths', []):
                    pk = (f, fn, tuple(p['path']))
                    self.paths[pk] = self.paths.get(pk, False) or bool(p['hit'])

    def summary(self, include=lambda f: True):
        def tally(d):
            keep = [v for k, v in d.items() if include(k[0])]
            return {'covered': sum(keep), 'total': len(keep),
                    'percent': round(100.0 * sum(keep) / len(keep), 2) if keep else 0.0}
        return {'lines': tally(self.lines), 'blocks': tally(self.blocks),
                'edges': tally(self.edges), 'paths': tally(self.paths)}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('requests_dir')
    ap.add_argument('--json')
    ap.add_argument('--t0', type=float, help='crawl start (epoch seconds); default: time of the first request')
    ap.add_argument('--checkpoints', type=float, nargs='*', default=[5, 10, 15, 30, 45, 60, 90, 120],
                    help='minutes after t0 at which cumulative coverage is reported')
    ap.add_argument('--exclude', nargs='*', default=[], help='ignore files whose path contains any of these')
    a = ap.parse_args()

    include = lambda f: not any(x in f for x in a.exclude)
    reqs = sorted(glob.glob(os.path.join(a.requests_dir, '*.json')) + glob.glob(os.path.join(a.requests_dir, '*.json.gz')))
    if not reqs:
        sys.exit('no request files in ' + a.requests_dir)

    def req_time(path):
        # file name is <epoch %014.4f>-<pid>.json[.gz]
        return float(os.path.basename(path).split('-')[0])

    t0 = a.t0 if a.t0 is not None else req_time(reqs[0])
    m = Merged()
    growth = []
    for r in reqs:
        d = json.load(gzip.open(r, 'rt') if r.endswith('.gz') else open(r))
        m.add({f: i for f, i in d['files'].items() if include(f)})
        s = m.summary()
        growth.append({'request': os.path.basename(r), 'uri': d.get('uri', ''),
                       'elapsed_s': round(req_time(r) - t0, 2),
                       **{k: s[k]['percent'] for k in s},
                       **{k + '_covered': s[k]['covered'] for k in s}})
    # cumulative coverage at fixed times: last request at or before each checkpoint
    checkpoints = []
    for mins in a.checkpoints:
        seen = [g for g in growth if g['elapsed_s'] <= mins * 60]
        g = seen[-1] if seen else None
        checkpoints.append({'minute': mins, 'requests': len(seen),
                            **({k: g[k] for k in ('lines', 'blocks', 'edges')} if g else
                               {'lines': 0.0, 'blocks': 0.0, 'edges': 0.0})})
    final = m.summary()

    print(f'Requests: {len(reqs)}, files: {len({k[0] for k in m.lines})}')
    print('\nCumulative coverage (Xdebug 2.5.5 on PHP 5.5):')
    for k in ('lines', 'blocks', 'edges', 'paths'):
        t = final[k]
        print(f"  {k:7s} {t['covered']:7d} / {t['total']:<7d} {t['percent']:.2f}%")
    print('\nGrowth by request (first 5, last 5):')
    show = growth if len(growth) <= 10 else growth[:5] + [None] + growth[-5:]
    for g in show:
        print('  ...' if g is None else
              f"  {g['uri'][:42]:42s} lines {g['lines']:6.2f}%  blocks {g['blocks']:6.2f}%  edges {g['edges']:6.2f}%")
    print('\nCoverage over time (cumulative, minutes after start):')
    for c in checkpoints:
        print(f"  {c['minute']:>5g} min  requests {c['requests']:5d}  lines {c['lines']:6.2f}%  blocks {c['blocks']:6.2f}%  edges {c['edges']:6.2f}%")
    if a.json:
        per_file = {}
        for f in sorted({k[0] for k in m.lines}):
            per_file[f] = m.summary(lambda x, f=f: x == f)
        json.dump({'final': final, 'perFile': per_file, 'growth': growth, 'checkpoints': checkpoints, 't0': t0}, open(a.json, 'w'), indent=1)
        print('\nWrote', a.json)


if __name__ == '__main__':
    main()
