#!/bin/bash
# Resumable pilot queue: PHP apps x SAFs x traversal, short budget. One run = one invocation of run-coverage-experiment.sh.
# A run is skipped if the status file already has "END <run> ok". Real exit codes, no `;`-chaining (see WORKLOG).
#
# Usage: scripts/crawl-bench/run_pilot.sh            (defaults below; override with env)
#   PILOT_APPS="mantisbt mrbs ppma"  PILOT_SAFS="fraggen rted pdiff"  PILOT_TRAVERSALS="bfs"  PILOT_MINUTES=10
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
APPS=${PILOT_APPS:-"mantisbt mrbs ppma"}
SAFS=${PILOT_SAFS:-"fraggen rted pdiff"}
TRAVERSALS=${PILOT_TRAVERSALS:-"bfs"}
MINUTES=${PILOT_MINUTES:-10}
KIND=${PILOT_KIND:-php}   # php -> run-coverage-experiment.sh (*-$SUF.json); js -> run-js-coverage-experiment.sh (*-branch.json)
if [ "$KIND" = js ]; then SCRIPT=run-js-coverage-experiment.sh; SUF=branch; STATUS="$ROOT/logs/pilot_js.status"; else SCRIPT=run-coverage-experiment.sh; SUF=php; STATUS="$ROOT/logs/pilot.status"; fi
mkdir -p "$ROOT/logs" "$ROOT/results/crawlbench"

# Chrome 114 (FragGen needs it) + a `timeout` shim (macOS has none) + the SNN env first on PATH for the SAF services
CHROME_DIR="${FRAGGEN_CHROME_DIR:-$HOME/fraggen-chrome}"
if [ "$(uname)" = Darwin ]; then DEFAULT_CHROME="$CHROME_DIR/chrome-mac-arm64/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing"; else DEFAULT_CHROME="$CHROME_DIR/chrome-linux64/chrome"; fi
export CHROME_BIN="${CHROME_BIN:-$DEFAULT_CHROME}"
export CHROMEDRIVER_BIN="${CHROMEDRIVER_BIN:-$CHROME_DIR/chromedriver}"
SHIM_DIR="$ROOT/logs/bin"; mkdir -p "$SHIM_DIR"
if ! command -v timeout > /dev/null 2>&1; then
  cat > "$SHIM_DIR/timeout" <<'EOF'
#!/usr/bin/env perl
my $d = shift @ARGV; $d =~ s/s$//;
my $pid = fork();
if ($pid == 0) { exec @ARGV or exit 127; }
$SIG{ALRM} = sub { kill 'TERM', $pid; sleep 2; kill 'KILL', $pid; waitpid($pid,0); exit 124; };
alarm $d; waitpid($pid,0); exit($? >> 8);
EOF
  chmod +x "$SHIM_DIR/timeout"
  export PATH="$SHIM_DIR:$PATH"
fi
[ -n "${SNN_ENV_BIN:-}" ] && export PATH="$SNN_ENV_BIN:$PATH" || export PATH="$HOME/miniconda3/envs/snn-ndd/bin:$PATH"

stamp() { date +%Y-%m-%d_%H:%M:%S; }
log() { echo "[$(stamp)] $*" | tee -a "$STATUS"; }

for app in $APPS; do
  for saf in $SAFS; do
    for trav in $TRAVERSALS; do
      run="${app}_${saf}_${trav}_${MINUTES}m"
      if grep -q "END $run ok" "$STATUS" 2>/dev/null; then log "SKIP $run (done)"; continue; fi
      log "START $run"
      before=$(ls -1t results/crawlbench/ 2>/dev/null | grep -c "${app}_${saf}_${trav}_.*-$SUF.json")
      CRAWLBENCH_MAX_RUNTIME=$MINUTES CRAWLBENCH_SAFS="$saf" CRAWLBENCH_TRAVERSALS="$trav" CRAWLBENCH_ASSUME_YES=1 \
        bash "scripts/crawl-bench/$SCRIPT" "$app" > "logs/pilot_${run}.log" 2>&1
      rc=$?
      after=$(ls -1t results/crawlbench/ 2>/dev/null | grep -c "${app}_${saf}_${trav}_.*-$SUF.json")
      cov=$(ls -1t results/crawlbench/${app}_${saf}_${trav}_*-$SUF.json 2>/dev/null | head -1)
      out=$(ls -1dt ICST20-submission-material-DANTE/crawljax/examples/out/${app}-${saf}-${trav}-${MINUTES}mins-* 2>/dev/null | head -1)
      # a run only counts when it exited 0, produced a NEW coverage file and an action log with decisions
      if [ $rc -eq 0 ] && [ "$after" -gt "$before" ] && { [ "$KIND" = js ] || [ -n "$out" ]; } && { [ "$KIND" = js ] || grep -q '"event":"NEW"' "$out/action-log.jsonl" 2>/dev/null; }; then
        log "END $run ok coverage=$cov out=$out"
      else
        log "END $run FAIL rc=$rc new_coverage_files=$((after-before)) out=${out:-none} (see logs/pilot_${run}.log)"
      fi
    done
  done
done
log "PILOT DONE"
