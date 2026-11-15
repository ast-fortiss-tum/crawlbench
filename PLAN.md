# Plan: CrawlBench study (paper 1)

Status: draft v3, 2026-11-15. Replaces v1/v2 of this file, which mislabelled the research questions (corrected here).

## Positioning

The structure follows the WebEmbed/SNN evaluation design that the repo already implements (`scripts/rq1`..`rq4`, README sections 1-4): near-duplicate detection, model quality against ground truth, code coverage, time efficiency. New on top of that: SAF x traversal as a joint factor with repeats, and fault exposure of the generated test suites through mutation testing.

The MSc thesis (Bui, 2026) is not yet known to the community; it ran each of 16 SAF x traversal configs once on 9 apps (coverage only, RQ3 below). Here that part becomes rigorous (repeats) and is placed in a full evaluation chain from SAF accuracy to model quality to coverage to fault exposure.

Closest published work: Liu, Yang, Zhang, Xie, arXiv 2606.16650 (Jun 2026): strategy x state abstraction on 6 SPAs, 5 repeats, 30 min, branch coverage, failure analysis. Their "SAF matters / no universal best" finding is confirmatory for us. Our differences: traversal as a joint factor (incl. Most-Actions-First and Priority-BFS), 5 PHP multi-page apps plus 4 SPAs, near-duplicate accuracy and model quality as explanatory layers, and mutation testing of generated suites.

## Research questions

- **RQ1, near-duplicate detection:** How accurately do the SAFs (RTED, PDiff, FragGen, SNN with doc2vec/BERT/MarkupLM/ModernBERT embeddings, WebEmbed-style baselines) classify state pairs as near-duplicates, within-app and across-app? (`scripts/rq1`; running now: across-app BERT contrastive.)
- **RQ2, model quality:** How well do the states each SAF yields match the ground-truth clusters in `dataset/clusters/*.json` (the 9 apps)? (`scripts/rq2`; offline, no crawling.)
- **RQ3, code coverage:** How do SAF x traversal combinations affect the coverage of the generated test suite across apps? With repeats: variance decomposition, effect sizes, rank stability across apps. Includes the question whether Most-Actions-First and Priority-BFS help, and when (e.g. session-gated Dimeshift). (`scripts/rq3`, `scripts/crawl-bench`)
- **RQ4, fault exposure (new):** Do configurations differ in the fault-detection ability (mutation score) of their generated test suites? Is coverage a good proxy for it, and does model quality (RQ2) or SAF accuracy (RQ1) predict it?
- **Secondary, time efficiency:** SAF training/inference time, crawl time, states per minute (existing `scripts/rq4`), as in the original design.

Cross-cutting analysis: does SAF accuracy (RQ1) explain model quality (RQ2), and does model quality explain coverage (RQ3) and mutation score (RQ4)? This chain is the explanatory story.

## Design (kept close to the thesis for RQ3)

- RQ3 factors: SAF {RTED, PDiff, FragGen, SNN} x traversal {BFS, DFS, MAF, PBFS}, 9 apps (5 PHP MPAs, 4 SPAs); thesis pre-configurations (form filling, crawl guards) unchanged.
- Budget 1 h per run as in the thesis unless the pilot shows much earlier saturation.
- Primary coverage metric: coverage of the DANTE-generated test suite. PHP: legacy Xdebug 2.2.4 setup as primary (replicability), new Xdebug 2.5.5 and JS branch coverage as additional results. Secondary: exploration coverage over time.
- Repeats set by the pilot, target 5 (3 in the pilot).
- Extra apps, granularity and the other extensions from `docs/STUDY_PLAN.md` (remote branch `origin/claude/web-crawlability-research-sy707c`) are optional, decided after the pilot.

## Mutation testing (RQ4)

- **Oracle rule:** run each suite on the original app first, 3x, and keep only tests that pass consistently. A mutant is killed only if such a test fails on the mutant.
- **Same mutant set per app across all configurations.** Fixed random sample per app (size from feasibility, e.g. 100-200), from the app's own code (exclude libraries/vendor). Report the score over all sampled mutants and over mutants on lines covered by at least one suite, since uncovered mutants survive trivially.
- **Tooling by stack (check in Phase 0):** SPAs: client-side JS with Stryker or a small operator set on the instrumented build (servers are Node, Java, Elixir, so start client-side). PHP MPAs: source-level mutation with a small operator set (conditionals, arithmetic, boundary, return values), since PHP tools such as Infection assume unit tests, not Selenium E2E suites.
- **Cost:** each mutant needs a redeploy and a full suite replay, so mutation cannot cover every suite. Run it on a subset of apps and configs (e.g. best and worst per SAF plus the heuristic traversals). Suite replay time is unknown; measure it in the pilot.
- Also report suite size, replay pass rate (flakiness), time per suite.

## Phases

### Phase 0: infrastructure readiness
- Finish and document the RQ1 runs (within/across-app for all embeddings; across-app bert running) and check RQ2 scripts run on current data.
- Smoke-run all 9 apps end to end with both crawl scripts (only petclinic and mantisbt fraggen+bfs exist; petclinic summary CSV had N/A fields). Verify the four SAF backends.
- Resumable run queue with real exit codes, one log per run, run IDs and seeds recorded; coverage and state counts logged over time.
- Mutation feasibility spike: one SPA (e.g. Dimeshift) and one PHP app (e.g. MRBS or PPMA), 20 mutants, one suite replay; measure time per mutant and kill rate; fix tooling and sample sizes.

### Phase 1: pilot
- 3 apps (e.g. Dimeshift, Pagekit or Phoenix, one MPA), all 16 configs, 3 repeats, coverage plus a small mutation run.
- Outputs: run-to-run variance, which thesis effects survive (Dimeshift traversal, FragGen on MPAs, SNN on Pagekit), saturation time, mutation cost per suite, whether mutation score separates configs.
- Go/no-go: fix repeats, budget, mutation sample size and the apps/configs for mutation.

### Phase 2: full study
- Crawls: 9 apps x 16 configs x repeats. At 1 h and 5 repeats: 720 h (about 30 days sequentially); check parallel crawls (ports, Docker, CPU) or reduce repeats where the pilot shows no effect.
- DANTE test generation and suite replay for every run; mutation on the selected subset.

### Phase 3: analysis
- RQ1/RQ2 as in the original design (per app and across-app, SAF comparison).
- RQ3: mixed-effects model / ANOVA with app as random factor, pairwise tests with Vargha-Delaney A12 and multiple-comparison correction, Kendall tau across apps, regret of global default configs, Dimeshift case study (crawl-path instrumentation, backtracking failures, session expiries).
- RQ4: mutation score per config, coverage vs mutation score correlation, ranking agreement between the two metrics, link to RQ1/RQ2.
- Secondary: efficiency, app characteristics vs sensitivity.

### Phase 4: writing
- Empirical study with practical guidance (default configuration plus conditional rules, cost of using a default). Threats: Crawljax/Chrome 83 age, calibration provenance of RTED/PDiff thresholds and the SNN (same dataset), mutant representativeness, single instrumentation.
- Cite the thesis; check venue policy on prior MSc thesis material and authorship with the thesis author.

## Open decisions
- Budget per run, repeats, parallel crawl capacity.
- Number of apps/configs that get mutation testing (after the spike).
- Whether to add apps beyond the nine; whether to port Addressbook and Claroline off the legacy PHP coverage setup.
- Target venue and deadline.
