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

## 7. Second move (2026-11-18): Linux machine to a new Linux machine, possibly a different Claude account

Written 2026-11-18. Source machine: Ubuntu 20.04, 4 CPUs, 15 GB RAM, GTX 1080 Ti (11 GB), Docker 28, no swap issues but crawls ran at load 2 to 4.
A different Claude account has **no memory and no transcript** of the earlier sessions. Everything it needs is in `CLAUDE.md`, `PLAN.md`, `WORKLOG.md` and this file.
Do not rely on `~/.claude/`.

### 7.1 What to prepare on the old machine (done once, before leaving)
1. Make sure nothing is running: `pgrep -af "crawljax|playwright|saf-|java"` and `docker ps`. The old machine was left idle on 2026-11-18.
2. Run `bash scripts/migrate/pack.sh` (writes `~/crawlbench-migration/`, 180 MB). It contains:
   - `git/uncommitted-tracked.patch`, `git/untracked-files.tgz`, `git/logs.tgz`, `git/HEAD.txt`: the uncommitted work (nothing was committed in the 2026-11-17/18 sessions).
   - `crawljax/crawljax-local-changes.patch` and `crawljax-untracked.tgz`: safety net for the DANTE/Crawljax directory.
   - `mlmt/`: our extension of MultilayerMT as a patch against the upstream commit in `upstream-commit.txt`, plus the pilot report.
   - `meta/models.tgz`: the Siamese weights, baseline SVMs and embeddings (the retrain is NOT bit-identical, keep these).
   - `conda/*.yml`, `conda/*.pip.txt`: exported Linux environments (`--no-builds`); `meta/machine.txt`: versions and Docker image IDs.
3. **Preferred way to carry the repo changes: commit and push** (the user decides; Claude does not commit unasked). Then the new machine just clones. The patch files are the fallback.
4. Big items, moved with rsync (about 15 GB, see section 1 for the table; paths are relative to the repo root):

       rsync -a --info=progress2 OLD:/home/andrea/repos/crawlbench/ICST20-submission-material-DANTE/ ./ICST20-submission-material-DANTE/   # 9.6 GB; add --exclude 'crawljax/examples/out/*/localhost' to save space
       rsync -a --info=progress2 OLD:/home/andrea/repos/crawlbench/{results,resources,logs} ./                                            # 1.3 GB + 3.8 GB + 15 MB
       rsync -a OLD:~/.cache/huggingface ~/.cache/                                                                                       # 0.6 GB, or let it re-download
       rsync -a OLD:~/crawlbench-migration ~/                                                                                            # the pack

   `results/crawlbench/` holds the Mac results (timestamps before 20261117_170000) and the Linux results (from then on); `results/crawlbench/linux-smoke/` holds smoke and diagnostic runs. Keep them apart: a third platform gets its own label, see 7.6.
5. Docker images: `docker pull` works for all of them (the 7 apps from `dockercontainervm/*`: `mantisbt:1.2.0`, `mrbs:1.4.9`, `ppma:0.6.0`, `dimeshift:non-empty-db`, `pagekit:latest`, `phoenix-trello:non-empty-db`, `petclinic-angular2:empty-db`; pull hit an IPv6 "network is unreachable" once, a retry worked).
   The `<app>-xdebug255` images are built locally: either `docker save mantisbt-xdebug255 mrbs-xdebug255 ppma-xdebug255 | gzip > xdebug.tgz` and `docker load`, or rebuild with `scripts/crawl-bench/php-coverage/Dockerfile.xdebug` (section 3).

### 7.2 What the new machine needs (sizing)
- x86-64 Ubuntu 22.04 or newer (Playwright 1.63 does not support 20.04; on 20.04 export `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu22.04-x64`, otherwise not needed).
- Docker with the user in the `docker` group (`sudo usermod -aG docker $USER`, then log in again; in an existing shell use `sg docker -c "..."`).
- Guideline for the 60-minute RQ3 campaigns and RQ4: 16 or more cores, 32 to 64 GB RAM, SSD. Each crawl lane needs about 3 GB (app containers plus Chrome plus Crawljax JVM) and a core or two. The GPU is only for the Siamese training/inference and is optional (CPU inference works, slower).
- Parallelism is currently limited to one lane per app (ports and container names are fixed per app in `run-js-coverage-experiment.sh` and `run-coverage-experiment.sh`). More lanes per app need configurable ports and container names (small change, not done).

### 7.3 Restore steps on the new machine (Claude can do these)
1. Clone: `git clone https://github.com/ast-fortiss-tum/crawlbench.git` (or apply `git/uncommitted-tracked.patch` with `git apply`, and unpack `untracked-files.tgz` in the repo root). Put the rsynced directories in place. `chmod +x scripts/crawl-bench/*.sh scripts/migrate/*.sh`.
2. Toolchain (all under `~/tools`, no root needed; add to `~/.bashrc`):
   - JDK **21** (Temurin 21 works; the Mac used 23): `JAVA_HOME=$HOME/tools/jdk`.
   - Maven 3.9.9: `$HOME/tools/apache-maven-3.9.9`.
   - Node 20.18.1: `$HOME/tools/node`.
   - `export PATH=$HOME/tools/node/bin:$JAVA_HOME/bin:$HOME/tools/apache-maven-3.9.9/bin:$PATH CHROME_BIN=$HOME/fraggen-chrome/chrome-linux64/chrome CHROMEDRIVER_BIN=$HOME/fraggen-chrome/chromedriver`
   - Chrome 114 and chromedriver 114: section 6 has the URLs. Install shared libraries as `ldd chrome | grep "not found"` says.
3. Maven (empty `~/.m2` on a new machine; the first crawl fails with "Could not find artifact crawljax-core:5.2.4-SNAPSHOT" otherwise):
   - `cd ICST20-submission-material-DANTE/crawljax && mvn install -DskipTests`
   - `cd ../dante && mvn install -DskipTests`, then `mvn dependency:get -Dartifact=org.testng:testng:7.0.0-beta1` and `-Dartifact=com.beust:jcommander:1.72` if the replay fails with `NoClassDefFoundError`.
4. Node: `cd scripts/crawl-bench/branch-coverage && npm install`.
5. Conda (accept the channel terms first: `conda tos accept`): `environment-snn-ndd.yml` pins macOS builds and does not solve on Linux. Use the exported files: `conda env create -n snn-ndd -f ~/crawlbench-migration/conda/snn-ndd.yml` and the same for `snn-ndd-gpu` (torch 2.6.0+cu124; transformers 5.x needs torch >= 2.6; also needs `imbalanced-learn` and `openpyxl`). If a solve fails, create from top-level packages and use the `.pip.txt` list as the reference. The GPU env is used for training and Siamese inference: `export SNN_ENV_BIN=$HOME/miniconda3/envs/snn-ndd-gpu/bin`.
6. Models: unpack `meta/models.tgz` in the repo root (gives `models/`, `baseline-models/`, `embeddings/`). Do not retrain unless needed; `across_app_baseline.py` and `modernbert_contrastive_classification.py` retrain them (the Siamese result is not identical to the earlier weights).
7. Petclinic: `export CRAWLBENCH_PETCLINIC_TOMCAT_PORT=9966`. The campaign script `scripts/crawl-bench/run_campaign_linux.sh` sets all of this.
8. RQ4 (mutation testing) tooling:
   - Clone MultilayerMT into a **durable** place (the working copy used so far lived in a session scratchpad that is lost): `git clone https://github.com/ast-fortiss-tum/multilayer-mt ~/tools/multilayer-mt && cd ~/tools/multilayer-mt && git checkout $(head -1 ~/crawlbench-migration/mlmt/upstream-commit.txt) && git apply scripts/rq4/mlmt-patches/mlmt-mutants-file.patch (also in the pack) && npm ci && npm run build`.
   - `PLAYWRIGHT_HOST_PLATFORM_OVERRIDE=ubuntu22.04-x64 npx playwright install chromium` (drop the variable on 22.04+).
   - The patch adds `--mutants-file <mutants-pwe<N>.json>` (config `mutantsFile`). It is **written but not yet built or tested** (the last `dist/` was built before the patch). First thing: build, then verify with the fixed-set run in 7.5.
   - The translated project `rq4/projects/dimeshift-rted/` (untracked; in `git/untracked-files.tgz`) has `node_modules` as a symlink to the MLMT checkout's `node_modules`: `ln -sfn ~/tools/multilayer-mt/node_modules rq4/projects/dimeshift-rted/node_modules`.
9. Smoke tests: section 4, plus for RQ4: start the dimeshift container (`cd ICST20-submission-material-DANTE/dante/docker/dimeshift && bash run-docker.sh -p yes -n rq4-dimeshift -a 3006 -d 3311`, wait about 60 s), then `cd rq4/projects/dimeshift-rted && node ~/tools/multilayer-mt/dist/src/cli.js run --max-mutants 20 --workers 3`. Expect a green baseline (10 passed) and about 50% mutation score (the pilot gave 10 killed of 19 executed; it varies with the sample). Stop and remove the container afterwards.

### 7.4 Status at the time of the move
See the top of `CLAUDE.md` ("State on 2026-11-18") and the last entries of `WORKLOG.md`. In short: RQ1/RQ2 done on all SAFs; RQ3 PHP repeats done (Mac), JS repeats done on Linux (45 of 48 runs OK; pagekit PDiff always yields 0 tests on Linux within 10 minutes, unresolved); RQ4 tooling built and piloted on one suite.

### 7.5 RQ4 design decisions made on 2026-11-18 (user approved)
- **Translate the suites** (DANTE selenium-actions to Playwright, `scripts/rq4/dante2pw.py`), do not extend MultilayerMT to Selenium. The grammar is only `get`, `click`, `clear`, `sendKeys`, `sleep`; one spec per path (paths are separated by `----`).
- **Implicit oracle** (the suites have no assertions), `scripts/rq4/templates/oracle.ts`: after every get/click it compares URL, title, visible text lines, visible control counts against `tests/golden.json`; at the end of a test it checks HTTP responses >= 400 / failed requests and console errors / page errors. `golden.json` is merged from at least 3 baseline runs in record mode (`ORACLE_MODE=record`, then `python3 scripts/rq4/dante2pw.py merge <project>`): required lines = seen in all runs, allowed = seen in any run, so run-to-run noise does not cause false kills. The dimeshift RTED baseline was stable (5 of 5 green, 0 noisy points, 1.3 to 1.4 min per replay).
- **Fixed mutant set per app** (PLAN.md rule): `--mutants-file` runs the same descriptors on every suite. Mutants are defined by operator + page key + selector/endpoint, so they are suite-independent; `testFiles` are recomputed per suite from its trace; mutants whose page/endpoint the suite never reaches are reported as SKIPPED with reason "not reached". **Scoring rule to apply in the analysis: kills / size of the fixed set (unreached counts as not detected)**, and also report kills / reached.
- Layers `dom` and `network`, `operatorSet: thesis`. The test-script layer is dropped (the AST rewriter targets TypeScript tests, our generated specs have almost no sites).
- Still to build: `scripts/rq4/mutant_union.py` (union the generated mutants of all suites of an app, seeded sample of a fixed size, e.g. 200 per app, stable ids), a driver that translates every suite of an app, records the golden file, and runs the fixed set; the analysis script. Cost indication: 20 mutants took about 15 minutes with 3 workers on the old machine (about 4.9 s/mutant on the todo demo, 30 to 50 s/mutant on dimeshift with sleeps scaled 1.0); `--sleep-scale 0.3` in the translator would cut that.
- App state: the dimeshift suites do not submit forms, so a shared app instance is fine. Check this per app (phoenix, pagekit, the PHP apps do change state) and restart the container between runs where needed.

### 7.6 Platform separation on a third platform
Results from the new machine are a third platform. Use a new cutoff timestamp (record it in `WORKLOG.md` at the first run) and extend `PLATFORM_CUTOFF` / `--platform` in `scripts/rq3/js_summary.py` (currently mac before and linux from `20261117_170000`). Do the repeats for one cell on one machine only.

### 7.7 Prompt for the new Claude session
> Read `CLAUDE.md`, `MIGRATION.md` (section 7), `PLAN.md` and the last entries of `WORKLOG.md`. Restore the environment following section 7.3, run the smoke tests, report what failed, and then continue with the "Next steps" in `CLAUDE.md`. Ask before committing, pushing, or sending anything outside the machine.
