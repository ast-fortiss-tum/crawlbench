# TODO / Future ideas

## Runtime SAF selection with a multi-armed bandit (separate paper, after the benchmark paper in PLAN.md)

Idea (2026-11-15): let the crawler choose the SAF (state abstraction function) at runtime, as a multi-armed bandit, instead of fixing one SAF per crawl.

Why:
- Overall goal is to suggest a good Crawljax configuration for an arbitrary app. SAF, traversal and input strategy depend on each other, so a static lookup per app-characteristic is hard to learn from ~10 apps.
- Learning online on the actual app avoids needing a predictor trained across apps.

Sketch:
- Arms: SAFs (dynamic-rted, dynamic-pdiff, dynamic-consensus, possibly the learned SNN from RQ1 as another arm).
- Reward: new coverage or new states per unit time (or per action). To be defined.
- Algorithm candidates: UCB, Thompson sampling, successive halving. Consider non-stationary rewards, since coverage saturates.
- Open issue: switching SAF mid-crawl changes what counts as "same state", so the state graph and traversal frontier need a consistent representation across arms.

Open questions / checks first:
- Does early coverage predict final coverage? Check on existing crawlbench time-series data.
- How much do config rankings agree across apps (e.g. Kendall's tau over the 12 SAF x traversal triples)? If stable, a good default may suffice.
- Repeats per cell: is run-to-run noise smaller than differences between configs?
- Use crawlbench as the benchmark to evaluate the bandit against the best fixed config and against a global default (regret).
