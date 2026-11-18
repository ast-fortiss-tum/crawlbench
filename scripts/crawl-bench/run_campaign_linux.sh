#!/bin/bash
# Linux overnight campaign: JS repeats (3 per cell, 10 min, BFS) for dimeshift pagekit phoenix petclinic x {fraggen rted pdiff siamese}.
# Waits for the Siamese weight training to finish, then runs two lanes in parallel (lane A: dimeshift -> pagekit, lane B: phoenix -> petclinic).
# Resumable (run_repeats.sh skips runs with "END ... ok" in logs/repeats_<app>.status). Start with:
#   setsid nohup sg docker -c "bash scripts/crawl-bench/run_campaign_linux.sh" > logs/campaign_linux.out 2>&1 &
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
ST=logs/campaign_linux.status
log() { echo "[$(date +%Y-%m-%d_%H:%M:%S)] $*" | tee -a "$ST"; }

export JAVA_HOME=$HOME/tools/jdk
export PATH=$HOME/tools/node/bin:$JAVA_HOME/bin:$HOME/tools/apache-maven-3.9.9/bin:$PATH
export CHROME_BIN=$HOME/fraggen-chrome/chrome-linux64/chrome CHROMEDRIVER_BIN=$HOME/fraggen-chrome/chromedriver
export SNN_ENV_BIN=$HOME/miniconda3/envs/snn-ndd-gpu/bin     # CUDA torch: Siamese inference on the GPU
export CRAWLBENCH_PETCLINIC_TOMCAT_PORT=9966
export KIND=js REPEATS=${REPEATS:-3} MINUTES=${MINUTES:-10} SAFS="${SAFS:-fraggen rted pdiff siamese}" TRAVERSAL=bfs

# 1. wait for the SNN training (pid in logs/train_snn.pid)
if [ -f logs/train_snn.pid ]; then
  pid=$(cat logs/train_snn.pid)
  while kill -0 "$pid" 2>/dev/null; do sleep 60; done
fi
n=$(ls models/acrossapp_modernbert_contrastive_*_cl_2_bs_128_ep_10_lr_2e-05_wd_0.01.pt 2>/dev/null | wc -l)
log "SNN training finished, $n/9 weight files"
[ "$n" -ge 9 ] || { log "ABORT: missing Siamese weights"; exit 1; }

# 2. lanes
lane() { for app in "$@"; do log "LANE app $app start"; bash scripts/crawl-bench/run_repeats.sh "$app"; log "LANE app $app end"; done; }
log "CAMPAIGN START repeats=$REPEATS minutes=$MINUTES safs=$SAFS"
lane dimeshift pagekit &
lane phoenix petclinic &
wait
log "CAMPAIGN DONE"
