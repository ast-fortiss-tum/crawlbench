# Moving crawlbench to another machine

Written 2026-11-17. The source machine was an Apple-silicon Mac (10 CPUs, 32 GB RAM, Docker VM 7.7 GB).

## 1. What git carries and what it does not

`git clone https://github.com/ast-fortiss-tum/crawlbench.git` gives you all scripts, `WORKLOG.md`,
`PLAN.md`, `TODO.md`, `CLAUDE.md` and `environment-snn-ndd.yml`. It does **not** give you the items below (all gitignored or outside the repo).

| Item | Size | How to move it |
|---|---|---|
| `ICST20-submission-material-DANTE/` (Crawljax + DANTE, with local modifications) | 8.9 GB | copy the directory (see 2) |
| `results/` (coverage data, raw per-request PHP dumps, RQ csv files) | 0.9 GB | copy |
| `logs/` (status files read by `scripts/rq3/repeats_summary.py`, per-run logs) | 13 MB | copy |
| `resources/` (entirely gitignored: embedding models 2.6 GB, baseline-runner 0.9 GB, doms 0.2 GB, baseline-dataset incl. `combinedEntries.json` 46 MB) | 3.7 GB | copy |
| Hugging Face cache (ModernBERT etc.) | 6.2 GB | copy `~/.cache/huggingface`, or let it re-download |
| Chrome 114 + chromedriver 114 (FragGen) | 0.4 GB | **do not copy** (the old one is a macOS arm64 build). On Ubuntu download the Linux builds, see 6 |
| conda env `snn-ndd` | 4.4 GB | recreate: `conda env create -f environment-snn-ndd.yml` |
| Docker images in use: `dockercontainervm/{pagekit,dimeshift,phoenix-trello,ppma:0.6.0,petclinic-angular2:empty-db}` | about 13 GB | `docker save` / `docker load`, or pull again |
| Docker images `{mantisbt,mrbs,ppma}-xdebug255` | about 3.2 GB | **`docker save` / `docker load` (recommended)**: the bases `dockercontainervm/mantisbt:1.2.0` and `mrbs:1.4.9` are no longer on the old machine, so rebuilding needs them pulled again (see 3) |

Rough total to copy by hand: about 10 GB without Docker images and caches.

## 2. The DANTE/Crawljax directory is not a clean checkout

`ICST20-submission-material-DANTE/crawljax` is a separate git repo (origin `kasunvimu8/NDD-Aware-TestGenerator`, one local commit "Initial commit")
with **many uncommitted local modifications** (69 files, about 3400 added lines: strategy selectors, SAF factories, per-app runners, the action-log
patch). Nothing in the main repo reproduces them, so copy the whole directory. `scripts/crawl-bench/crawljax-patches/README.md` documents only
the changes made in the 2026-11 sessions (ActionLogPlugin, core event fields, DANTE `DriverProvider` Chrome pin).

Suggested copy, keeping the useful part of the 5.9 GB of crawl output (`crawljax/examples/out`: per-run `action-log.jsonl` is small, `localhost/` holds
screenshots/DOMs):

    rsync -a --info=progress2 OLD:/path/crawlbench/ICST20-submission-material-DANTE/ ./ICST20-submission-material-DANTE/
    # smaller: add  --exclude 'crawljax/examples/out/*/localhost'   (keeps action logs, drops screenshots/DOMs)

As a safety net, also keep a diff: `git -C ICST20-submission-material-DANTE/crawljax diff HEAD > crawljax-local-changes.patch`
(plus the untracked files from `git status`).

## 3. Environment on the new machine

- macOS arm64 (Linux works in principle; the scripts use `memory_pressure`, `sysctl vm.swapusage` and `caffeinate`, which are macOS only).
- Java 23, Maven 3.10, Docker (amd64 images run under emulation on arm64), Python 3, conda.
- Docker VM memory of at least 8 GB. Do not run other heavy jobs at the same time: time-budgeted crawls are load-sensitive.
- `timeout` is missing on macOS; the run scripts create a perl stand-in in `logs/bin/` (a no-op where `timeout` exists).
- Rebuild the PHP coverage images (Xdebug 2.5.5):

      cd scripts/crawl-bench/php-coverage
      docker build --platform linux/amd64 --build-arg BASE=dockercontainervm/mantisbt:<tag> -t mantisbt-xdebug255 -f Dockerfile.xdebug .
      # same for mrbs and ppma (BASE=dockercontainervm/ppma:0.6.0)

- FragGen needs Chrome 114 and chromedriver 114: `export CHROME_BIN=".../Google Chrome for Testing"` and `CHROMEDRIVER_BIN=.../chromedriver`
  (the runner scripts default to `~/fraggen-chrome`, override with `FRAGGEN_CHROME_DIR`).
- The SNN env must be first on PATH for the SAF services: `SNN_ENV_BIN` (default `~/miniconda3/envs/snn-ndd/bin`).
- Make scripts executable: `chmod +x scripts/crawl-bench/*.sh` (git keeps the mode, copies may not).

## 4. Smoke test before trusting anything

    # PHP, 2 minutes, one app, one SAF
    CRAWLBENCH_MAX_RUNTIME=2 CRAWLBENCH_SAFS=rted CRAWLBENCH_TRAVERSALS=bfs CRAWLBENCH_ASSUME_YES=1 \
        bash scripts/crawl-bench/run-coverage-experiment.sh mrbs
    # expect: rc 0, results/crawlbench/mrbs_rted_bfs_*-php.json, action-log.jsonl with "event":"NEW" lines
    # JS, one app
    PILOT_KIND=js PILOT_APPS=dimeshift PILOT_SAFS=rted PILOT_MINUTES=2 bash scripts/crawl-bench/run_pilot.sh

Then check `scripts/rq3/repeats_summary.py` and `scripts/rq3/js_summary.py` still print the old numbers from the copied `results/` and `logs/`.

## 5. After arrival: what is open

See `CLAUDE.md` (handoff for Claude Code) and `WORKLOG.md`.

## 6. Ubuntu (Linux) notes: to be done by Claude Code on the new machine

The user does not need to migrate Chrome. On arrival Claude should set this up and adapt the scripts:

- **Chrome 114 and chromedriver 114 for Linux** (FragGen needs exactly 114):
  - Chrome: `https://storage.googleapis.com/chrome-for-testing-public/114.0.5735.90/linux64/chrome-linux64.zip` (about 300 MB, checked 2026-11-17).
  - chromedriver: `https://chromedriver.storage.googleapis.com/114.0.5735.90/chromedriver_linux64.zip` (the old location; the same file name under the Chrome for Testing bucket returns 404).
  - Unzip into `~/fraggen-chrome/`, then `export CHROME_BIN=~/fraggen-chrome/chrome-linux64/chrome` and `export CHROMEDRIVER_BIN=~/fraggen-chrome/chromedriver` (or whatever the unzip layout is). `dante/chromedriver-linux64` contains only licence files, no binary.
  - Chrome 114 needs the usual shared libraries (`libnss3`, `libatk-bridge2.0-0`, `libgbm1`, `libxss1`, `libasound2` and similar); install what `ldd chrome | grep "not found"` reports.
- **macOS-only code in the scripts** (make it work on both, e.g. branch on `uname`):
  - `scripts/crawl-bench/run_pilot.sh` and `run_repeats.sh` default `CHROME_BIN` to the macOS path (`chrome-mac-arm64/Google Chrome for Testing.app/...`); fix the default or always export the two variables first.
  - `run_repeats.sh`: `free_pct()` uses `memory_pressure`, `conditions()` uses `sysctl vm.loadavg` / `vm.swapusage`. On Linux use `/proc/meminfo` (MemAvailable / MemTotal), `/proc/loadavg` and SwapTotal-SwapFree. Without the fix the memory guard silently does nothing and the logged conditions are blank.
  - `kill_orphans()` greps for `fraggen-chrome`; it still works if Chrome stays under `~/fraggen-chrome`.
  - `timeout` exists on Linux; the perl stand-in is skipped automatically.
  - BSD vs GNU differences: `sed -i` (GNU takes no suffix argument), `date`, `ls -1t`, `stat`. Check any script that uses them.
- **Docker:** the app images are linux/amd64. On x86 Ubuntu they run natively (faster than the emulated runs here; run times and request counts will not be comparable to the Mac results, so keep platforms apart or note it). On arm64 Ubuntu they need emulation (`--platform linux/amd64`, qemu-user-static). Check host-port publishing and `localhost` access from the containers; the smoke test in 4 will show problems.
- **Java 23, Maven, conda:** install and re-run the smoke tests. Heap and thread limits may differ.
- **Comparability:** results from the new machine are a different platform (CPU, load, Docker native vs emulated). Put them in separate result files or label them, and run the repeats for a given cell on one machine only.
