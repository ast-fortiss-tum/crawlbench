# Crawljax patches (the ICST20-submission-material-DANTE tree is gitignored, so they are kept here)

## ActionLogPlugin (2026-11-16)
Copy `ActionLogPlugin.java` to `ICST20-submission-material-DANTE/crawljax/examples/src/main/java/com/crawljax/examples/` and
register it in `UnifiedRunner.runCrawl`, right after `builder.setOutputDirectory(customOutput);`:

    builder.addPlugin(new ActionLogPlugin(customOutput));

Then `cd examples && mvn -o -q compile`. It writes `action-log.jsonl` into the crawl output directory: one line per action
outcome (SAF verdict NEW / REVISIT, reached state, source state, action, wall-clock ms). Used by
`scripts/rq3/coverage_complementarity.py --action-log` to attribute coverage to states and SAF decisions.

## Running FragGen on macOS
FragGen needs Chrome 114. Crawljax honours `CHROME_BIN` and `CHROMEDRIVER_BIN`; point them at Chrome for Testing 114.0.5735.90
(mac-arm64) and its chromedriver, e.g. in ~/fraggen-chrome/. macOS has no `timeout`; put a shim on PATH for
run-coverage-experiment.sh.

## Core patch: expose the action behind each SAF verdict (needed by ActionLogPlugin)
Crawljax calls OnNewState/OnRevisitState plugins without the action, so record it on the context.
Apply, then `cd core && mvn -o -q install -DskipTests` (installs crawljax-core into ~/.m2; examples resolve it from there).

1. `core/.../core/CrawlerContext.java`: add fields + accessors
       private volatile com.crawljax.core.state.Eventable lastEventable;   get/setLastEventable
       private volatile String lastEventKind = "";                         get/setLastEventKind
   (kinds: "decision" fresh SAF verdict, "replay" backtracking re-fire, "urlload" URL-loaded state, "index" first page)
2. `core/.../core/state/StateMachine.java`, `switchToStateAndCheckIfClone`, right after `addStateToCurrentState(newState, event)`:
       context.setLastEventable(event); context.setLastEventKind("decision");
3. `core/.../core/Crawler.java`:
   - `tryToFireEvent`, before `plugins.runOnRevisitStatePlugins(context, curState)`:
       context.setLastEventable(clickable); context.setLastEventKind("replay");
   - `checkOnURLState`, before `plugins.runOnNewStatePlugins(context, newState)`:
       context.setLastEventable(null); context.setLastEventKind("urlload");
   - index creation, before `plugins.runOnNewStatePlugins(context, index)`:
       context.setLastEventable(null); context.setLastEventKind("index");
Note: `context.getCrawlPath()` can throw (null path), so never rely on it in plugins.
