#!/bin/bash
# Runs the remaining RQ1 baselines and all RQ2 scripts sequentially; continues on failure.
# Status in logs/rq1_rq2_remaining.status (exit codes captured before any other command), logs per step.
cd "$(dirname "$0")/../.." || exit 1
PY=/Users/stocco/miniconda3/envs/snn-ndd/bin/python
export PYTHONPATH="$PWD"
mkdir -p logs results/rq1 results/rq2 resources/csv_results_table
ST=logs/rq1_rq2_remaining.status
run() {  # name, script
  echo "[$(date +%F_%T)] START $1" >> $ST
  $PY "$2" > "logs/$1.log" 2>&1
  rc=$?
  echo "[$(date +%F_%T)] END $1 exit=$rc" >> $ST
}
run rq1_baseline_within  scripts/rq1/baseline-classification/within_app_baseline.py
run rq1_baseline_across  scripts/rq1/baseline-classification/across_app_baseline.py
run rq2_snn              scripts/rq2/snn.py
run rq2_a_other_baselines scripts/rq2/a-other-baselines.py
run rq2_b_other_baselines scripts/rq2/b-other-baselines.py
run rq2_a_webembed       scripts/rq2/a-webembed.py
run rq2_b_webembed       scripts/rq2/b-webembed.py
echo "[$(date +%F_%T)] ALL DONE" >> $ST
