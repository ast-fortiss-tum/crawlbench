#!/bin/bash
# One LANE of the repeats study: runs SAF x repetition for ONE app, one run at a time (an app's ports, container name and
# coverage dir are fixed, so repeats of the same app cannot overlap). Start one lane per app to parallelise across apps.
# SAF order rotates with the repetition (rep 1: A B C, rep 2: B C A, ...) so drift in machine load is spread over SAFs.
# Resumable: a run is skipped when logs/repeats_<app>.status already has "END <run> ok".
#
# Usage: scripts/crawl-bench/run_repeats.sh <app>
#   REPEATS=5  MINUTES=10  SAFS="fraggen rted pdiff"  TRAVERSAL=bfs
set -u
APP=${1:?usage: run_repeats.sh <app>}
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
REPEATS=${REPEATS:-5}
MINUTES=${MINUTES:-10}
SAFS=(${SAFS:-fraggen rted pdiff})
TRAV=${TRAVERSAL:-bfs}
STATUS="$ROOT/logs/repeats_${APP}.status"
mkdir -p "$ROOT/logs" "$ROOT/results/crawlbench"

CHROME_DIR="${FRAGGEN_CHROME_DIR:-$HOME/fraggen-chrome}"
export CHROME_BIN="${CHROME_BIN:-$CHROME_DIR/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing}"
export CHROMEDRIVER_BIN="${CHROMEDRIVER_BIN:-$CHROME_DIR/chromedriver}"
SHIM_DIR="$ROOT/logs/bin"; mkdir -p "$SHIM_DIR"
if ! command -v timeout > /dev/null 2>&1; then
  [ -x "$SHIM_DIR/timeout" ] || {
    cat > "$SHIM_DIR/timeout.tmp.$$" <<'EOF'
#!/usr/bin/env perl
my $d = shift @ARGV; $d =~ s/s$//;
my $pid = fork();
if ($pid == 0) { exec @ARGV or exit 127; }
$SIG{ALRM} = sub { kill 'TERM', $pid; sleep 2; kill 'KILL', $pid; waitpid($pid,0); exit 124; };
alarm $d; waitpid($pid,0); exit($? >> 8);
EOF
    chmod +x "$SHIM_DIR/timeout.tmp.$$"; mv "$SHIM_DIR/timeout.tmp.$$" "$SHIM_DIR/timeout"; }
  export PATH="$SHIM_DIR:$PATH"
fi
export PATH="${SNN_ENV_BIN:-$HOME/miniconda3/envs/snn-ndd/bin}:$PATH"

log() { echo "[$(date +%Y-%m-%d_%H:%M:%S)] $*" | tee -a "$STATUS"; }
MIN_FREE_PCT=${MIN_FREE_PCT:-25}
free_pct() { memory_pressure 2>/dev/null | awk '/free percentage/ {gsub("%","",$NF); print $NF}'; }
conditions() { echo "load1=$(sysctl -n vm.loadavg | awk '{print $2}') swap_used_mb=$(sysctl -n vm.swapusage | sed -E 's/.*used = ([0-9.]+)M.*/\1/') free_mem_pct=$(free_pct)"; }
# crawls that stop on the time limit leave their Chrome behind; kill only orphans (parent died), never another lane's browser
kill_orphans() { ps -Ao pid,ppid,command | awk '$2==1 && /fraggen-chrome/ {print $1}' | xargs kill -9 2>/dev/null; true; }
n=${#SAFS[@]}
for rep in $(seq 1 "$REPEATS"); do
  for i in $(seq 0 $((n - 1))); do
    saf=${SAFS[$(( (i + rep - 1) % n ))]}
    run="${APP}_${saf}_${TRAV}_${MINUTES}m_rep${rep}"
    if grep -q "END $run ok" "$STATUS" 2>/dev/null; then log "SKIP $run (done)"; continue; fi
    kill_orphans
    while [ "$(free_pct)" -lt "$MIN_FREE_PCT" ] 2>/dev/null; do log "WAIT free memory $(free_pct)% < ${MIN_FREE_PCT}%"; sleep 60; done
    log "START $run $(conditions)"
    before=$(ls -1 results/crawlbench/ 2>/dev/null | grep -c "^${APP}_${saf}_${TRAV}_.*-php.json$")
    CRAWLBENCH_MAX_RUNTIME=$MINUTES CRAWLBENCH_SAFS="$saf" CRAWLBENCH_TRAVERSALS="$TRAV" CRAWLBENCH_ASSUME_YES=1 \
      bash scripts/crawl-bench/run-coverage-experiment.sh "$APP" > "logs/repeats_${run}.log" 2>&1
    rc=$?
    after=$(ls -1 results/crawlbench/ 2>/dev/null | grep -c "^${APP}_${saf}_${TRAV}_.*-php.json$")
    cov=$(ls -1t results/crawlbench/${APP}_${saf}_${TRAV}_*-php.json 2>/dev/null | head -1)
    out=$(ls -1dt ICST20-submission-material-DANTE/crawljax/examples/out/${APP}-${saf}-${TRAV}-${MINUTES}mins-* 2>/dev/null | head -1)
    if [ $rc -eq 0 ] && [ "$after" -gt "$before" ] && [ -n "$out" ] && grep -q '"event":"NEW"' "$out/action-log.jsonl" 2>/dev/null; then
      log "END $run ok coverage=$cov out=$out $(conditions)"
    else
      log "END $run FAIL rc=$rc new_coverage_files=$((after-before)) out=${out:-none} (see logs/repeats_${run}.log) $(conditions)"
    fi
  done
done
log "LANE DONE $APP"
