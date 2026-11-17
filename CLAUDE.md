# Handoff for Claude Code (read this first on a new machine)

Written 2026-11-17 so a fresh session can resume. Full history is in `WORKLOG.md`; the study design is in `PLAN.md`;
moving instructions are in `MIGRATION.md`.

## Standing rules from the user
- **Keep a worklog:** after each meaningful step append a dated entry to `WORKLOG.md` (at the repo root) before ending the turn.
- **Status updates every 60 minutes** while long jobs run (the user asked for this on 2026-11-17).
- Do not deviate much from the thesis plan (PLAN.md): RQ1 near-duplicate detection, RQ2 model quality, RQ3 code coverage, RQ4 fault exposure (mutation testing), time efficiency secondary. The user wants repeats beyond the thesis's single run per cell.
- Commit only when asked. Do not push without being asked. End commits with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Keep the user's name and project details out of requests to outside services.
- Overall goal: given an arbitrary web app, recommend a good Crawljax configuration (SAF, traversal, input). The runtime-SAF bandit (`TODO.md`) is a separate, later paper.

## State on 2026-11-17 (nothing running)
Done:
- **RQ1/RQ2** for all SAFs including FragGen (8 apps; MRBS has no FragGen verdicts, so precision and recall are n/a there).
- **PHP repeats (RQ3):** mantisbt, mrbs, ppma × {FragGen, RTED, PDiff, Siamese} × BFS × 10 min × 5 repeats, 60 runs all ok. Summary: `python3 scripts/rq3/repeats_summary.py` → `results/crawlbench/repeats_summary.csv`. Lines coverage means: mantisbt FragGen 28.8 / Siamese 28.7 / RTED 28.3 / PDiff 24.9; mrbs RTED 41.5 / PDiff 41.4 / FragGen 40.2 (bimodal 41.8 or 37.7) / Siamese 37.7; ppma FragGen 45.7 / RTED 41.6 / PDiff 41.4 (RTED and PDiff bimodal 38.8 or 45-46) / Siamese 38.8 (always the low mode).
- **JS pilot (RQ3):** dimeshift, pagekit, phoenix, petclinic × {RTED, FragGen, PDiff, Siamese} (dimeshift has no Siamese run), BFS, 10 min, 1 run each. Summary on a common denominator: `python3 scripts/rq3/js_summary.py` → `results/crawlbench/js_summary.csv`. Statement coverage %: dimeshift FragGen 27.2 / RTED 18.3 / PDiff 15.3; pagekit FragGen 18.8 / Siamese 17.8 / RTED 17.5 / PDiff 9.3; phoenix all about 51 except Siamese 47.0; petclinic about 73.5 to 77.4 for all.

## Next steps (in the order agreed with the user)
1. **JS repeats:** 3 per cell (user earlier wanted up to 5; PHP got 5). Use `KIND=js REPEATS=3 MINUTES=10 SAFS="fraggen rted pdiff siamese" bash scripts/crawl-bench/run_repeats.sh <app>` (one lane per app; apps have different ports so lanes can run in parallel if memory allows, but start with 1 to 2). Run dimeshift Siamese too. Each JS run takes 20 to 40 min including test replay. Note the JS status line for `run_repeats.sh` has `out=` empty (the crawl output is moved); success is "rc 0 and a new `-branch.json`". `repeats_summary.py` reads only PHP `-php.json` results; extend it (or use `js_summary.py` with repeats) for JS.
2. **Mutation-testing feasibility:** about 20 mutants on one PHP app and one JS app, to cost out RQ4 (mutation scope is an open decision in PLAN.md).
3. **Per-state coverage attribution for JS apps** (only PHP has it: `scripts/rq3/coverage_complementarity.py`; JS has no per-request timestamps and `branch-coverage.mjs` stores only counts per script, so union or complementarity across SAFs is not possible without changing it).
4. Follow-ups: investigate the mantisbt PDiff rep3 run with only 26 requests; fix the Siamese SAF service not being killed at run end (see below); decide extra apps (port Addressbook and Claroline off the legacy PHP coverage setup), venue and deadline, run budget (10 min now; thesis used 60).
5. Parked: SNN triplet threshold calibration (triplet across-app F1 0.17 to 0.38, contrastive 0.45 to 0.77); FragGen on MRBS via own page-type labels; WebPageBench-inspired ideas; the bandit paper.

## Things that bite (learned the hard way)
- **Machine load:** crawls are time-budgeted and sensitive to load and swap. Reps 1 to 3 on mantisbt/mrbs ran under heavy load and made about half the requests of reps 4 to 5. Do not run other heavy jobs (e.g. sbt) at the same time; report request counts next to coverage. `run_repeats.sh` waits for free memory (`MIN_FREE_PCT`, default 25) and logs load/swap.
- **Do not restart quickly after killing runs:** stale cleanup traps of the old run remove the new run's containers and SAF services. Wait until the old script has exited (check `ps`).
- **Orphans:** a crawl that stops on the time limit leaves Chrome behind; `run_repeats.sh` kills orphans (ppid 1, command matches `fraggen-chrome`). The Siamese service (`saf-snn.py`) was NOT being stopped at run end (7-hour-old instances found); killed manually. Fix `kill-saf-services.sh`/the stop function before the next campaign.
- **A `LANE DONE` line does not mean the last run succeeded.** Check `END ... ok` lines (`grep -c "END.* ok" logs/repeats_<app>.status`).
- **Exit codes:** the coverage scripts used `set -e`; teardown commands must end with `|| true`. Scripts must be executable and run via `bash`.
- **macOS:** no `timeout` (perl shim, takes seconds with an optional `s` suffix, NOT `m`), foreground `sleep` is blocked in Claude Code (use Monitor), zsh treats `=====` as a command, replace scripts used by running processes atomically (temp file + `os.replace`).
- **FragGen** needs Chrome 114 + chromedriver 114 via `CHROME_BIN`/`CHROMEDRIVER_BIN`. The DANTE test replay `DriverProvider` was patched to honour `CHROME_BIN` (documented in `scripts/crawl-bench/crawljax-patches/README.md`).
- **Siamese** runs use `acrossapp_modernbert` **contrastive** (`SNN_SETTING` override); the `run-saf-snn.sh` default is triplet.
- **JS coverage percentages** from `branch-coverage.mjs` use the scripts a run loaded as denominator; always compare with `js_summary.py` (common denominator).
- **PPMA is bimodal** (about 38.8% or 45-46% lines): a single run can misrank SAFs; MRBS FragGen is bimodal too. Always use repeats.
- **PHP crawls end by exhaustion** in 1 to 7 minutes on ppma/mrbs; the 10 minute budget rarely binds there. JS crawls often exhaust within 2 minutes too (dimeshift RTED/PDiff).
- Docker: images for the PHP apps are `<app>-xdebug255`, built from `scripts/crawl-bench/php-coverage/Dockerfile.xdebug`. Petclinic needs `CRAWLBENCH_PETCLINIC_TOMCAT_PORT=9966`. Do not touch the user's `mlmt-mediawiki-*` containers.

## Key scripts
- `scripts/crawl-bench/run-coverage-experiment.sh <php-app>` / `run-js-coverage-experiment.sh <js-app>`: one crawl plus coverage; env `CRAWLBENCH_MAX_RUNTIME`, `CRAWLBENCH_SAFS`, `CRAWLBENCH_TRAVERSALS`, `CRAWLBENCH_ASSUME_YES`, `SNN_SETTING`.
- `scripts/crawl-bench/run_pilot.sh` (`PILOT_KIND=php|js`) and `run_repeats.sh <app>` (`KIND=php|js`, `REPEATS`, `MINUTES`, `SAFS`, `TRAVERSAL`, `HARD_LIMIT_MIN`): resumable queues; status in `logs/`.
- `scripts/rq3/repeats_summary.py` (PHP noise), `js_summary.py` (JS, common denominator), `coverage_complementarity.py` (PHP per-state attribution and set complementarity).
- ActionLogPlugin (per-action NEW/REVISIT log) is in the gitignored Crawljax clone; copy kept in `scripts/crawl-bench/crawljax-patches/`.
