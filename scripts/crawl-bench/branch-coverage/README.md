# Branch (and statement/function/line) coverage for the JS apps

DANTE's built-in metric (`coverage_type=bytes`) is the share of script characters covered by V8 *function-level*
ranges, averaged over scripts. Judge reports Istanbul-style **statements / branches / functions / lines**
instead. `branch-coverage.mjs` computes those from raw V8 *block* coverage.

## How it fits together
1. `CodeCoverage.java` (DANTE) starts precise **block** coverage per test (as before, but `detailed=true`), disables
   Chrome's cache over CDP, takes the coverage after every test and dumps the raw V8 ranges to
   `<test-suite>/coverage-reports/v8-raw/` (`scripts/<key>.js|json`, `tests/<test>/<key>.json`, `tests.txt`).
2. `node branch-coverage.mjs <test-suite>/coverage-reports/v8-raw --json out.json` parses each script with
   acorn, enumerates statements, functions and branch arms (if/else, ternary, switch cases, every operand of
   `&&`/`||`/`??`) and marks an item covered when V8's innermost range containing it has count > 0.
   Output: cumulative totals, per-script numbers, and per-test (partial) and cumulative growth.

Setup: `npm install` in this folder.

## Caveats
- An `if` without `else` counts only its explicit arm (V8 has no range for the implicit else), so branch
  totals are a bit lower than Istanbul's.
- Only items inside the script's `lineRanges` (app code, from the source map) are counted.
- Chrome's code cache serves pre-compiled scripts *without* block-coverage data. Without disabling the cache,
  V8 reports only function-level ranges (we saw 0-8 block ranges instead of ~320) and branch coverage looks
  like ~98% because every arm inherits "covered" from its function. The `Network.setCacheDisabled` call in
  `CodeCoverage` is therefore essential.
- Keeping coverage running across tests ("start once, take after each test") crashed Chrome's renderer after
  ~13 tests on Chrome 157, so coverage is started and stopped per test like the original.
- Not comparable one-to-one with Judge's numbers (they instrument the app with Istanbul during the crawl; we
  replay DANTE's generated test suite).
