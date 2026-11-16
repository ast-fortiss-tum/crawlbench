#!/usr/bin/env python3
"""Does one SAF cover code another SAF misses? And which crawl state/action earned the coverage?

Inputs are PHP request-dump directories written by branch_coverage_prepend.php (one JSON per request, file name =
epoch seconds), one per run. Runs are labelled, e.g. the SAF name:

    coverage_complementarity.py --app mantisbt \
        rted=results/crawlbench/mantisbt_dynamic-rted_bfs_..-php-requests \
        pdiff=results/crawlbench/mantisbt_dynamic-pdiff_bfs_..-php-requests \
        [--action-log rted=out/.../action-log.jsonl ...] [--json out.json]

1. Set-level complementarity (per metric: lines, blocks, edges):
   coverage of each run, code covered ONLY by that run, union of all runs, gain of the union over the best single run,
   pairwise Jaccard.
2. Per route (URI path, a stand-in for "page"): same, restricted to the code executed by requests to that route.
3. Per state/action (needs the action log written by ActionLogPlugin): every request's *new* code (not yet covered
   earlier in the same run) is credited to the first logged action outcome at or after the request time, i.e. the
   action that caused the request. Gives per-state coverage gain and the gain per SAF decision (new vs revisit).
"""
import argparse
import bisect
import glob
import gzip
import json
import os
import sys
from urllib.parse import urlparse

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'crawl-bench', 'php-coverage'))
from merge_xdebug_coverage import items  # noqa: E402

METRICS = ('lines', 'blocks', 'edges')


def request_elements(files):
    """Covered elements of one request as {metric: set}."""
    out = {m: set() for m in METRICS}
    for f, info in files.items():
        for line, st in items(info.get('lines', {})):
            if st == 1:
                out['lines'].add((f, int(line)))
        for fn, fdata in items(info.get('functions', {})):
            for _, b in items(fdata.get('branches', {})):
                bk = (f, fn, b['op_start'])
                if b['hit']:
                    out['blocks'].add(bk)
                if len(b['out']) >= 2:
                    for tgt, hit in zip(b['out'], b['out_hit']):
                        if hit:
                            out['edges'].add(bk + (tgt,))
    return out


def universe_of(files, uni):
    """Executable elements (covered or not) of a request, so percentages share one denominator."""
    for f, info in files.items():
        for line, st in items(info.get('lines', {})):
            if st in (1, -1):
                uni['lines'].add((f, int(line)))
        for fn, fdata in items(info.get('functions', {})):
            for _, b in items(fdata.get('branches', {})):
                bk = (f, fn, b['op_start'])
                uni['blocks'].add(bk)
                if len(b['out']) >= 2:
                    for tgt in b['out']:
                        uni['edges'].add(bk + (tgt,))


def load_run(path, uni):
    reqs = sorted(glob.glob(os.path.join(path, '*.json')) + glob.glob(os.path.join(path, '*.json.gz')))
    if not reqs:
        sys.exit('no request files in ' + path)
    run = {'covered': {m: set() for m in METRICS}, 'routes': {}, 'requests': []}
    for r in reqs:
        d = json.load(gzip.open(r, 'rt') if r.endswith('.gz') else open(r))
        t_ms = float(os.path.basename(r).split('-')[0]) * 1000.0
        universe_of(d['files'], uni)
        el = request_elements(d['files'])
        route = urlparse(d.get('uri', '')).path or '(none)'
        new = {m: el[m] - run['covered'][m] for m in METRICS}
        for m in METRICS:
            run['covered'][m] |= el[m]
            run['routes'].setdefault(route, {k: set() for k in METRICS})[m] |= el[m]
        run['requests'].append({'t_ms': t_ms, 'route': route, 'new': {m: len(new[m]) for m in METRICS}})
    return run


def pct(a, b):
    return round(100.0 * a / b, 2) if b else 0.0


def jaccard(a, b):
    u = a | b
    return round(len(a & b) / len(u), 3) if u else 1.0


def complementarity(runs, uni):
    res = {}
    for m in METRICS:
        sets = {k: r['covered'][m] for k, r in runs.items()}
        union = set().union(*sets.values())
        best = max(sets, key=lambda k: len(sets[k]))
        res[m] = {
            'universe': len(uni[m]),
            'union': {'covered': len(union), 'percent': pct(len(union), len(uni[m]))},
            'best_single': {'run': best, 'covered': len(sets[best]), 'percent': pct(len(sets[best]), len(uni[m]))},
            'union_gain_over_best_pp': round(pct(len(union), len(uni[m])) - pct(len(sets[best]), len(uni[m])), 2),
            'per_run': {k: {'covered': len(s), 'percent': pct(len(s), len(uni[m])),
                            'only_this_run': len(s - set().union(*[o for kk, o in sets.items() if kk != k]))
                            if len(sets) > 1 else len(s)} for k, s in sets.items()},
            'jaccard': {f'{a}~{b}': jaccard(sets[a], sets[b]) for i, a in enumerate(sets) for b in list(sets)[i + 1:]},
        }
    return res


def per_route(runs, metric='lines'):
    routes = sorted({rt for r in runs.values() for rt in r['routes']})
    rows = []
    for rt in routes:
        sets = {k: r['routes'].get(rt, {metric: set()})[metric] for k, r in runs.items()}
        union = set().union(*sets.values())
        if not union:
            continue
        row = {'route': rt, 'union': len(union)}
        for k, s in sets.items():
            others = set().union(*[o for kk, o in sets.items() if kk != k]) if len(sets) > 1 else set()
            row[k] = len(s)
            row[k + '_only'] = len(s - others)
        rows.append(row)
    return sorted(rows, key=lambda r: -r['union'])


def load_action_log(path):
    ev = []
    for line in open(path):
        line = line.strip()
        if not line:
            continue
        j = json.loads(line)
        if j.get('event') in ('NEW', 'REVISIT'):
            ev.append(j)
    ev.sort(key=lambda j: j['t_ms'])
    return ev


def attribute(run, ev):
    """Credit each request's new code to the first action outcome at/after the request time."""
    times = [e['t_ms'] for e in ev]
    def label(e):
        # fresh SAF decisions are NEW / REVISIT; backtracking replays, URL loads and the index are kept apart
        return e['event'] if e.get('kind', 'decision') == 'decision' else e['kind']

    labels = sorted({label(e) for e in ev})
    by_state, by_verdict, unattributed = {}, {l: {m: 0 for m in METRICS} for l in labels}, {m: 0 for m in METRICS}
    n_verdict = {l: 0 for l in labels}
    for e in ev:
        n_verdict[label(e)] += 1
    for rq in run['requests']:
        i = bisect.bisect_left(times, rq['t_ms'])
        if i >= len(ev):
            for m in METRICS:
                unattributed[m] += rq['new'][m]
            continue
        e = ev[i]
        st = by_state.setdefault(e['state'], {'actions': 0, **{m: 0 for m in METRICS}})
        for m in METRICS:
            st[m] += rq['new'][m]
            by_verdict[label(e)][m] += rq['new'][m]
    for e in ev:
        by_state.setdefault(e['state'], {'actions': 0, **{m: 0 for m in METRICS}})['actions'] += 1
    return {'by_state': by_state,
            'by_saf_verdict': {v: {'decisions': n_verdict[v], **by_verdict[v],
                                   **{m + '_per_decision': round(by_verdict[v][m] / n_verdict[v], 3) if n_verdict[v] else 0.0
                                      for m in METRICS}} for v in by_verdict},
            'unattributed_after_last_action': unattributed}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('runs', nargs='+', help='label=requests_dir')
    ap.add_argument('--action-log', nargs='*', default=[], help='label=action-log.jsonl')
    ap.add_argument('--app', default='')
    ap.add_argument('--json')
    ap.add_argument('--top', type=int, default=15, help='routes / states to print')
    a = ap.parse_args()

    uni = {m: set() for m in METRICS}
    runs = {}
    for spec in a.runs:
        label, path = spec.split('=', 1)
        runs[label] = load_run(path, uni)
    out = {'app': a.app, 'runs': {k: len(r['requests']) for k, r in runs.items()}, 'complementarity': complementarity(runs, uni)}

    print(f"App {a.app or '?'}; runs: " + ', '.join(f"{k} ({n} requests)" for k, n in out['runs'].items()))
    for m in METRICS:
        c = out['complementarity'][m]
        print(f"\n[{m}] universe {c['universe']}; union {c['union']['percent']}%; best single "
              f"{c['best_single']['run']} {c['best_single']['percent']}%; union gain over best {c['union_gain_over_best_pp']} pp")
        for k, v in c['per_run'].items():
            print(f"   {k:20s} {v['percent']:6.2f}%   only this run: {v['only_this_run']}")
        for k, v in c['jaccard'].items():
            print(f"   Jaccard {k}: {v}")

    out['per_route_lines'] = per_route(runs, 'lines')
    print(f"\nPer route (lines executed by requests to the route), top {a.top} by union:")
    for r in out['per_route_lines'][:a.top]:
        print('  ' + f"{r['route'][:44]:44s} union {r['union']:5d}  " +
              '  '.join(f"{k} {r[k]}(+{r[k + '_only']})" for k in runs))

    if a.action_log:
        out['attribution'] = {}
        logs = dict(s.split('=', 1) for s in a.action_log)
        for label, path in logs.items():
            ev = load_action_log(path)
            att = attribute(runs[label], ev)
            out['attribution'][label] = att
            print(f"\n[{label}] coverage gain attributed to SAF decisions ({len(ev)} action outcomes):")
            for v, d in att['by_saf_verdict'].items():
                print(f"   {v:8s} decisions {d['decisions']:5d}  new lines {d['lines']:6d} ({d['lines_per_decision']}/decision)  "
                      f"blocks {d['blocks']}  edges {d['edges']}")
            top = sorted(att['by_state'].items(), key=lambda kv: -kv[1]['lines'])[:a.top]
            print(f"   top states by new lines:")
            for s, d in top:
                print(f"     {s:12s} actions {d['actions']:4d}  lines {d['lines']:6d}  blocks {d['blocks']:6d}  edges {d['edges']:6d}")
            print(f"   unattributed (after last action): {att['unattributed_after_last_action']}")

    if a.json:
        json.dump(out, open(a.json, 'w'), indent=1)
        print('\nWrote', a.json)


if __name__ == '__main__':
    main()
