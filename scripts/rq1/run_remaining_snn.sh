#!/bin/bash
# Runs remaining RQ1 SNN contrastive configs sequentially; continues on failure.
cd "$(dirname "$0")/../.." || exit 1
mkdir -p logs
for cfg in within-app-classification/doc2vec across-app-classification/doc2vec \
           within-app-classification/bert within-app-classification/markuplm \
           across-app-classification/markuplm; do
  name=$(echo "$cfg" | sed 's#-app-classification/#_#')
  echo "[$(date +%F_%T)] START $cfg" >> logs/rq1_remaining_snn.status
  /Users/stocco/miniconda3/envs/snn-ndd/bin/python scripts/rq1/${cfg%/*}/${cfg#*/}_contrastive_classification.py > logs/rq1_${name}_contrastive.log 2>&1
  echo "[$(date +%F_%T)] END $cfg exit=$?" >> logs/rq1_remaining_snn.status
done
echo "[$(date +%F_%T)] ALL DONE" >> logs/rq1_remaining_snn.status
