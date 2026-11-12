# Study Plan: State-Abstraction Granularity × Traversal in Model-Based Web Crawling

*Draft v0.1, written to continue the discussion. Builds on the MSc thesis by X. P. Bui (2026)
and is positioned against Liu et al., "Understanding Automated Web GUI Testing: An Empirical
Study Across Exploration Strategies and State Abstractions", arXiv:2606.16650.*

---

## 1. Positioning

Liu et al. compare strategy **families** (model-based, RL, LLM) and six state abstractions, with
**one threshold per abstraction**. Model-based crawling is always Crawljax's default traversal
order, and they measure **exploration-time client-side coverage** on 6 SPAs (5 runs, means only).

Their headline claim is that strict, fine-grained abstractions favour model-based crawling and
compact ones favour RL. That claim conflates *abstraction technique* with *abstraction
granularity*: their Table 6 state counts range from 6 to 3,774. They also never vary traversal
order, and never look past exploration to the generated tests.

**Our study is a controlled study of the model-based design space.** It separates technique from
granularity, varies traversal order, measures the quality of the inferred model against ground
truth, and follows each configuration through to the generated test suite.

Working title: *"Granularity, Not Technique? A Controlled Study of State Abstraction and
Traversal in Model-Based Web Test Generation"*

Venue target: ICSE / FSE / ISSTA (or TOSEM / EMSE for the long version).

## 2. Research questions and hypotheses

| RQ | Question | Hypothesis (to pre-register) |
|----|----------|------------------------------|
| **RQ1 Granularity** | How does abstraction granularity, varied *within* each technique, affect model quality, coverage and failures? | H1a: coverage shows an inverted-U over granularity. H1b: once techniques are matched at the same granularity, differences between techniques shrink substantially (tests Liu et al.'s confound). H1c: the best granularity for crawling ≠ the F1-optimal operating point for near-duplicate classification. |
| **RQ2 Traversal** | Does traversal order (DFS, BFS, MAF, PBFS, Random) matter, and does it interact with granularity? | H2a: the main effect is small. H2b: the interaction is significant. Coarse abstractions cause early termination, where order matters little; fine abstractions explode the frontier, where order decides what is reached. H2c: order matters in session-gated apps (Dimeshift). |
| **RQ3 Test-suite quality** | How do abstraction × traversal choices carry over to the generated test suites? | H3a: exploration coverage overestimates test-suite coverage. H3b: the gap and the flakiness grow with finer granularity. H3c: mutation score correlates more with model F1 than with exploration coverage. |
| **RQ4 Mechanisms & cost** | Why do configurations differ? What role do termination, backtracking failures, abstraction-function (SAF) cost and app traits play? | H4: much of the variance is explained by (#states, termination time, backtracking-failure rate). App traits (session gating, template redundancy) predict how sensitive an app is to configuration. |
| **RQ5 (optional) Cross-paradigm** | Does the granularity effect hold for RL (WebExplor), reusing Liu et al.'s package? | H5: for RL, the best granularity is coarser than for model-based crawling. This replicates Liu et al.'s claim with granularity controlled. |

## 3. Independent variables

### 3.1 Abstraction technique
- StrCmp (Crawljax default, the no-near-duplicate-detection baseline)
- RTED, PDiff
- FragGen (used as an abstraction function, not as a separate tool)
- WebEmbed, SNN [Kan+26], Judge (from Liu et al.'s package)

### 3.2 Granularity (key novelty)
We make granularity **comparable across techniques** by fixing each technique's *operating point*
on the labelled YSM20 near-duplicate pairs. To avoid leakage, calibration is leave-one-app-out.

| Level | Definition |
|-------|------------|
| Fine (strict) | Threshold at which near-duplicate recall = 0.5 (states rarely merged) |
| Balanced | F1-optimal threshold |
| Coarse (compact) | Threshold at which near-duplicate precision = 0.8 (states aggressively merged) |

- **Threshold-based techniques:** the distance threshold is swept.
- **Classifiers (SNN, WebEmbed, Judge):** the decision threshold on the probability or distance is swept.
- **Check:** we report the resulting #states per run to confirm the levels actually differ in granularity.

### 3.3 Traversal
- DFS (Crawljax default)
- BFS
- Most Actions First (MAF)
- Priority BFS (PBFS)
- **Random frontier** (new, lower-bound baseline)

The priority score in PBFS must be specified for every technique (see §8).

### 3.4 Budget
- **Primary:** 30 min, matching Liu et al. Coverage is sampled every minute, so results at smaller budgets can be read off the same runs.
- **Long budget:** 120 min on a subset of 3 apps.
- **No restart hack.** Early termination is an outcome we measure, not something to mask. A restart variant is run only for RQ5 comparability.

## 4. Subjects

| Group | Apps | Coverage instrumentation |
|-------|------|--------------------------|
| SPA (DIG / Liu et al.) | Dimeshift, Pagekit, Petclinic, Phoenix, Retroboard, Splittypie | Client side: NYC branch coverage (reuse Liu et al.'s instrumented builds). Server side where feasible: NYC for Node backends, Xdebug for Pagekit |
| MPA (PHP) | Addressbook, Claroline, MantisBT, MRBS, PPMA | Server side: Xdebug + php-code-coverage |

- **Ground truth for model quality:** the YSM20 clusters (`dataset/clusters/*.json`) cover the 9 original apps. They do not cover Retroboard or Splittypie, so those two get coverage and failure metrics only.
- **Third-party code:** library and framework code is excluded from coverage via explicit allow-lists, so that MRBS's 160k client LOC does not distort its results.

## 5. Dependent variables (one row per run)

### Exploration
- Client and server branch/line coverage, final value and coverage-over-time (AUC)
- #states, #transitions, maximum and mean depth, unique actions fired
- Backtracking failures
- Termination time (budget utilisation)

### Model quality
- Precision, recall and F1 of the state partition against the YSM20 clusters (pairwise, i.e. on state pairs)
- Liu et al.-style state coverage against a union graph

### Test suite (DANTE)
- #tests and mean length
- Replay pass rate over 3 replays (flakiness)
- Test-suite coverage
- **Mutation score**: Stryker for JS, Infection or MAEWU-style operators for PHP. Run on a subset (see §6).

### Failures
- Console errors and server 5xx / PHP errors, deduplicated with Liu et al.'s script

### Cost
- #SAF calls
- SAF time as a share of the run
- Actions per minute

## 6. Experimental design (staged, to keep compute feasible)

A full factorial (7 × 3 × 5 × 11 × 10) is about 11.5k runs, roughly 5,800 crawl-hours. We stage it
instead.

| Stage | Design | Runs | Crawl-hours |
|-------|--------|------|-------------|
| S0 Pilot | 3 apps × 2 configs × 20 reps → variance estimate, power analysis to fix the number of repetitions | 120 | 60 |
| S1 Granularity (RQ1) | 7 techniques × 3 levels × DFS × 11 apps × 10 reps | 2,310 | 1,155 |
| S2 Traversal (RQ2) | 5 traversals × 3 technique–level picks (best / coarse / fine from S1) × 11 apps × 10 reps (DFS cells reused) | ~1,320 new | ~660 |
| S3 RL cross-check (RQ5, optional) | WebExplor × 7 × 3 × 6 SPAs × 5 reps | 630 | 315 |
| S4 Test suites (RQ3) | DANTE generation + 3 replays for all S1/S2 runs. Mutation on 4 apps × 6 extreme configs × 5 reps | — | ~300 (replay) |

- **Total:** about 2,500 crawl-hours. With 10 parallel isolated workers (one Docker network per run), that is about 11 days of wall-clock time.
- **Analysis plan:** fixed before S1 starts and recorded in `docs/analysis-plan.md`.

## 7. Analysis

### Per app
- Aligned-rank-transform ANOVA (technique × granularity × traversal)
- Pairwise Wilcoxon tests with Holm correction
- Vargha–Delaney Â12 effect sizes

### Across apps
- Mixed-effects model with app as a random effect, on logit(coverage), with technique, granularity, traversal and their interactions as fixed effects
- Variance decomposition, done properly this time (the thesis's "SAF explains most" claim did not hold up)

### Rankings and relationships
- Scott–Knott ESD rankings of configurations
- Kendall τ correlations between exploration coverage, model F1, test-suite coverage and mutation score (RQ3)

### Mechanisms (RQ4)
- Regression of coverage on #states, termination time and backtracking-failure rate
- Case studies driven by the logs, e.g. the Dimeshift session hypothesis, which is tested directly

### Reporting
- Every per-run CSV, scripts and notebooks are published in the replication package
- Coverage heatmaps and coverage-over-time curves

## 8. Engineering backlog (before S0)

1. **Version the Crawljax fork.** `UnifiedRunner`, the traversal strategies and the SAF hooks go into this repo, as a submodule or a fork pinned to a commit.
2. **One coverage protocol.**
   - Exploration coverage is sampled *during* the crawl.
   - Test-suite coverage is measured *after* the crawl, by replaying the DANTE suite against a fresh container.
   - Both are used for SPAs and MPAs alike.
3. **Upgrade the browser stack.** Move off Chrome 83 and align with Liu et al. (Chromium 112). FragGen's OpenCV dependency needs checking.
4. **Add a threshold parameter to every SAF service** (`saf-snn.py`, `saf-other-baseline.py`), plus Judge and WebEmbed services taken from Liu et al.'s package.
5. **Embedding cache in the SNN service**, keyed by DOM hash, so that SAF cost does not confound the fixed time budget.
6. **Fully specify PBFS:**
   - Dissimilarity = min distance to the visited set, using each technique's continuous score.
   - The score is computed at insertion.
   - Its cost is counted inside the budget.
7. **Random-frontier traversal** for Crawljax.
8. **Fix the script bugs found earlier:**
   - Timeout `*120` → `*60`
   - `/tmp` vs `$TEMP_DIR` mismatch in the JS script
   - `crawl_log` captured from stdout
   - `read -p` prompt blocking unattended runs
   - Missing per-run CSV for the PHP apps
9. **Non-interactive driver:** a run matrix (YAML) → isolated containers → per-run result directories. It must be resumable and record seeds and run IDs.
10. **Per-run metrics extractor:** `result.json` + logs + coverage → one CSV row. Includes the state-to-cluster mapping for model F1.
11. **DB reset per run** (`docker compose down -v` + seeding), verified by checksum.
12. **Instrument the crawler:** coverage snapshots every minute, SAF call log, backtracking-failure log.

## 9. Threats and mitigations

| Threat | Mitigation |
|--------|------------|
| Crawljax is outdated or unmaintained | Pin and document versions. Keep the RL cross-check (S3) so results are not Crawljax-only. |
| Granularity calibration depends on the YSM20 labels | Leave-one-app-out calibration. Report the realised #states. Sensitivity check with a 4th level. |
| Ground-truth mapping of states that are new (not in YSM20) | Nearest labelled exemplar + manual validation of a sample (report agreement, Cohen's κ). |
| Weak failure oracle | Mutation score as the main fault-detection measure. Console and server errors are secondary. |
| Compute cost | Staged design, power analysis in S0, parallel workers. |
| Overlap with Liu et al. | Cite them explicitly. Our study is complementary: we control granularity, vary traversal and measure downstream test quality, which they leave open. |

## 10. Timeline (indicative)

| Weeks | Work |
|-------|------|
| 1–2 | Inspect Liu et al.'s replication package, finish backlog items 1–5, pilot infrastructure |
| 3–4 | Backlog items 6–12, S0 pilot + power analysis, freeze the analysis plan |
| 5–7 | S1 granularity runs |
| 8–9 | S2 traversal runs (+ S3 if in scope) |
| 10–11 | S4 test suites + mutation, analysis |
| 12–14 | Writing |

## 11. Tomorrow: first steps

1. Download Liu et al.'s replication package (figshare 10.6084/m9.figshare.31148509, 13 GB) and
   check it against this list:
   - raw per-run data
   - SAF Flask services (Judge, WebEmbed)
   - NYC-instrumented apps + Docker setup
   - the Crawljax restart mechanism
   - thresholds and state-count logs
   - the failure deduplication script
   - Chromium/driver pinning
   - licence
2. Decide which Crawljax base to use: theirs, or the thesis fork. Same question for the Chromium version.
3. Decide the scope:
   - Include S3 (RL)?
   - An LLM reference point (GPTWeb), which is costly?
   - Mutation tooling
4. Confirm the compute budget (number of parallel workers available).

## 12. Open decisions

- Number of granularity levels: 3 vs 4.
- Subject set: 11 apps, or add newer SPAs to answer the criticism that the subjects are dated.
- Whether to pre-register (e.g. as a registered report at ICSE/ESEM).
