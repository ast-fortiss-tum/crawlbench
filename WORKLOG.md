# Work Log

Running log of what we do in this repo. Newest entries first.

## 2026-11-15

- Reviewed and committed pending work in 3 commits (coverage/branch-coverage scripts, MarkupLM float32 fix + RQ1 scripts, worklog). `logs/` left uncommitted.
- Fixed across-app bert title (`acrossapp_modernbert` -> `acrossapp_bert`). A first launch with the unfixed title (sed -i failed on macOS) was killed after ~1 epoch, before saving anything. Relaunched: `logs/rq1_across_bert_contrastive.log`, status `logs/rq1_across_bert.status`. Computing fresh bert embeddings first.

## 2026-11-14

- 18:37 update: across-app markuplm DONE (17:35-18:17, xlsx `results/rq1/acrossapp_markuplm_results_contrastive_...181756.xlsx`; phoenix F1 0.93, petclinic 0.75 weighted). ALL markuplm runs finished; update cron stopped. Remaining RQ1 gap: across-app bert contrastive (title bug).
- 18:07 update: within-app markuplm DONE (17:23-17:35, petclinic weighted F1 0.992). across-app markuplm RUNNING (7 of 9 apps tested; pagekit F1 class1 0.61, recall 0.96).
- MarkupLM MPS crash root cause: cached MarkupLM embeddings were float16 when no zero-padding happened (e.g. claroline, across addressbook; `torch.cat` with fp32 padding promoted others to fp32), while the siamese head is fp32 -> Metal dtype assertion. Fix in `scripts/utils/embedding.py`: cast embeddings to float32 when computing and when loading the cache (no recompute needed).
- Resumed markuplm: `scripts/rq1/run_markuplm_snn.sh` (within then across; status in `logs/rq1_markuplm.status`, logs `logs/rq1_{within,across}_markuplm_contrastive.log`, real exit codes). Training now runs on MPS (within-app claroline reached epoch 7 of 15). No periodic updates (stopped by user).

## 2026-11-13

- Stopped the 30-min progress updates at user's request (nothing running).
- 21:07 update: queue finished (ALL DONE 20:45). within-app bert contrastive DONE (20:25-20:39; xlsx `results/rq1/withinapp_bert_results_contrastive_...203939.xlsx`; petclinic weighted F1 0.999). within-app markuplm and across-app markuplm CRASHED within ~3 min each (embeddings were computed and cached; crash at start of training): Metal assertion `MPSNDArrayMatrixMultiplication ... Destination NDArray and Accumulator NDArray cannot have different datatype` on the MPS device. The `exit=0` in `logs/rq1_remaining_snn.status` is wrong for these (the `$(date)` in the echo resets `$?`); trust the logs. Not rerun yet. Options: force CPU for markuplm, or find the fp16/fp32 mix in the MarkupLM training path. Still skipped: across-app bert (title bug).
- 20:37 update: across-app doc2vec contrastive DONE (19:57-20:25, exit 0; xlsx `results/rq1/acrossapp_doc2vec_results_contrastive_...202512.xlsx`; weighted F1 ~0.87-0.88 on phoenix/petclinic). within-app bert RUNNING since 20:25 (6-7 of 9 apps tested so far; dimeshift weighted F1 0.87, pagekit 0.87). Queue: within markuplm, across markuplm.
- 20:07 update: within-app doc2vec contrastive DONE (19:42-19:57, exit 0; results xlsx `results/rq1/withinapp_doc2vec_results_contrastive_...195700.xlsx`; weighted F1 ~0.996-0.998 on phoenix/petclinic). across-app doc2vec RUNNING (3 of 9 apps tested: addressbook F1 0.90, claroline 0.94 weighted). Remaining queue: within bert, within markuplm, across markuplm.
- Started keeping this log (requested by Andrea).
- Project goal (per Andrea): replicate Phuoc's thesis and extend it. The coverage experiments below are presumably part of that; details to be filled in.
- RQ1 (near-duplicate detection, SNN) requested. Chose scope: remaining SNN configs. Already done: across-app ModernBERT triplet (results/rq1 xlsx, 2026-11-12).
  - Added `scripts/rq1/run_remaining_snn.sh`: runs sequentially within doc2vec, across doc2vec, within bert, within markuplm, across markuplm (contrastive). Logs in `logs/rq1_*_contrastive.log`, progress in `logs/rq1_remaining_snn.status`. Launched in background on Apple M2 Pro. First launch failed instantly (system python lacks `imblearn`); relaunched with the `snn-ndd` conda env python (`/Users/stocco/miniconda3/envs/snn-ndd/bin/python`). User wants progress updates every 30 min.
  - Skipped across-app bert contrastive: `across-app-classification/bert_contrastive_classification.py` sets `title = "acrossapp_modernbert"` while using `bert-base-uncased`, which would reuse the ModernBERT embedding cache/models. Needs a title fix (or switch to ModernBERT) first.
- State at start of session: uncommitted work on coverage experiments
  - Modified: `.gitignore`, `scripts/crawl-bench/run-coverage-experiment.sh`, `scripts/crawl-bench/run-js-coverage-experiment.sh`
  - New (untracked): `scripts/crawl-bench/branch-coverage/` (JS branch coverage, `branch-coverage.mjs`), `scripts/crawl-bench/php-coverage/` (Xdebug Dockerfile, prepend script, merge script), `web-apps-main/README.md`
  - Not yet reviewed or committed.
- No TODO/FIXME markers found in `scripts/crawl-bench/` or `web-apps-main/README.md`.
