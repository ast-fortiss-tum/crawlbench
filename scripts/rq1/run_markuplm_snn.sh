#!/bin/bash
cd "$(dirname "$0")/../.." || exit 1
PY=/Users/stocco/miniconda3/envs/snn-ndd/bin/python
for s in within across; do
  echo "[$(date +%F_%T)] START $s markuplm" >> logs/rq1_markuplm.status
  $PY scripts/rq1/${s}-app-classification/markuplm_contrastive_classification.py > logs/rq1_${s}_markuplm_contrastive.log 2>&1
  rc=$?
  echo "[$(date +%F_%T)] END $s markuplm exit=$rc" >> logs/rq1_markuplm.status
done
echo "[$(date +%F_%T)] ALL DONE" >> logs/rq1_markuplm.status
