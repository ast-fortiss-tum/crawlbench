#!/bin/bash
# ModernBERT SNN runs (within contrastive, within triplet, across contrastive), then RQ2 SNN again.
# Waits for the earlier finish queue to end first (shared GPU).
cd "$(dirname "$0")/../.." || exit 1
PY=/Users/stocco/repos/tools/crawlbench/../../../../Users/stocco/miniconda3/envs/snn-ndd/bin/python
PY=/Users/stocco/miniconda3/envs/snn-ndd/bin/python
export PYTHONPATH="$PWD"
until grep -q "ALL DONE" logs/rq1_rq2_finish.status 2>/dev/null; do sleep 30; done
ST=logs/rq1_modernbert.status
run() { echo "[$(date +%F_%T)] START $1" >> $ST; $PY "$2" > "logs/$1.log" 2>&1; rc=$?; echo "[$(date +%F_%T)] END $1 exit=$rc" >> $ST; }
run rq1_across_modernbert_contrastive scripts/rq1/across-app-classification/modernbert_contrastive_classification.py
run rq1_within_modernbert_contrastive scripts/rq1/within-app-classification/modernbert_contrastive_classification.py
run rq1_within_modernbert_triplet scripts/rq1/within-app-classification/modernbert_triplet_classification.py
run rq2_snn_v3 scripts/rq2/snn.py
echo "[$(date +%F_%T)] ALL DONE" >> $ST
