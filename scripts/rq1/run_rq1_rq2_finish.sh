#!/bin/bash
# Finishes RQ1/RQ2: across-app webembed baseline, remaining SNN triplet variants, then RQ2 again.
cd "$(dirname "$0")/../.." || exit 1
PY=/Users/stocco/miniconda3/envs/snn-ndd/bin/python
export PYTHONPATH="$PWD"
ST=logs/rq1_rq2_finish.status
run() { echo "[$(date +%F_%T)] START $1" >> $ST; $PY "$2" > "logs/$1.log" 2>&1; rc=$?; echo "[$(date +%F_%T)] END $1 exit=$rc" >> $ST; }
run rq1_baseline_across_v2 scripts/rq1/baseline-classification/across_app_baseline.py
run rq2_a_webembed_v2 scripts/rq2/a-webembed.py
run rq2_b_webembed_v2 scripts/rq2/b-webembed.py
run rq1_within_doc2vec_triplet scripts/rq1/within-app-classification/doc2vec_triplet_classification.py
run rq1_within_bert_triplet scripts/rq1/within-app-classification/bert_triplet_classification.py
run rq1_within_markuplm_triplet scripts/rq1/within-app-classification/markuplm_triplet_classification.py
run rq1_across_doc2vec_triplet scripts/rq1/across-app-classification/doc2vec_triplet_classification.py
run rq1_across_markuplm_triplet scripts/rq1/across-app-classification/markuplm_triplet_classification.py
run rq2_snn_v2 scripts/rq2/snn.py
echo "[$(date +%F_%T)] ALL DONE" >> $ST
