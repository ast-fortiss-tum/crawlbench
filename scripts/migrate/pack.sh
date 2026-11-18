#!/bin/bash
# Pack everything that git does NOT carry and that is small enough for one archive (< 200 MB).
# Big items (DANTE dir 9.6 GB, resources/ 3.8 GB, results/ 1.3 GB, HF cache, Docker images) are moved with rsync / docker save: see MIGRATION.md section 7.
# Usage: bash scripts/migrate/pack.sh [OUT_DIR]      (default ~/crawlbench-migration)
set -u
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="${1:-$HOME/crawlbench-migration}"
mkdir -p "$OUT"/{git,crawljax,mlmt,conda,meta}
cd "$ROOT"
export PATH=$HOME/tools/node/bin:$HOME/tools/jdk/bin:$HOME/tools/apache-maven-3.9.9/bin:$PATH

# 1. uncommitted state of the main repo (the user decides when to commit; this is the safety net)
git rev-parse HEAD > "$OUT/git/HEAD.txt"
git diff HEAD > "$OUT/git/uncommitted-tracked.patch"
git ls-files --others --exclude-standard | grep -v '^logs/' | grep -v 'node_modules\|\.mutants/\|/\.mlmt/' > "$OUT/git/untracked-files.txt"
tar czf "$OUT/git/untracked-files.tgz" -T "$OUT/git/untracked-files.txt" 2>/dev/null
tar czf "$OUT/git/logs.tgz" logs 2>/dev/null

# 2. Crawljax/DANTE local changes (the directory itself is also rsynced; this is the safety net)
if [ -d ICST20-submission-material-DANTE/crawljax/.git ]; then
  (cd ICST20-submission-material-DANTE/crawljax && git diff HEAD > "$OUT/crawljax/crawljax-local-changes.patch"
   git ls-files --others --exclude-standard | grep -v '^examples/out/' | tar czf "$OUT/crawljax/crawljax-untracked.tgz" -T - 2>/dev/null)
fi

# 3. MultilayerMT working copy (our extension: --mutants-file). Upstream commit + patch.
MLMT="${MLMT_DIR:-}"
if [ -z "$MLMT" ]; then MLMT=$(ls -d /tmp/claude-*/*/*/scratchpad/mlmt/repo 2>/dev/null | head -1); fi
if [ -n "$MLMT" ] && [ -d "$MLMT/.git" ]; then
  (cd "$MLMT" && git rev-parse HEAD > "$OUT/mlmt/upstream-commit.txt"; git remote -v | head -1 >> "$OUT/mlmt/upstream-commit.txt"
   git diff HEAD > "$OUT/mlmt/mlmt-mutants-file.patch")
fi

# 4. trained models, embeddings (Siamese weights, baseline SVMs): small, and the retrain is not bit-identical, so keep them
tar czf "$OUT/meta/models.tgz" models baseline-models embeddings 2>/dev/null

# 5. environments
CONDA="$HOME/miniconda3/bin/conda"
for e in snn-ndd snn-ndd-gpu; do
  "$CONDA" env export -n $e --no-builds > "$OUT/conda/$e.yml" 2>/dev/null
  "$HOME/miniconda3/envs/$e/bin/pip" freeze > "$OUT/conda/$e.pip.txt" 2>/dev/null
done
{
  echo "date: $(date -Is)"; echo "uname: $(uname -a)"; echo "cpus: $(nproc)"; free -g | sed -n 2p
  java -version 2>&1 | head -1; mvn -v | head -1; node -v
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader 2>/dev/null
  echo "chrome: $("$HOME/fraggen-chrome/chrome-linux64/chrome" --version 2>/dev/null)"
  echo "chromedriver: $("$HOME/fraggen-chrome/chromedriver" --version 2>/dev/null | head -1)"
  echo "playwright browsers: $(ls ~/.cache/ms-playwright 2>/dev/null | tr '\n' ' ')"
  echo "--- docker images"; sg docker -c "docker images --format '{{.Repository}}:{{.Tag}} {{.ID}} {{.Size}}'" 2>/dev/null | grep -v 'asyrp\|nvidia\|hello'
} > "$OUT/meta/machine.txt"
echo "packed to $OUT"; du -sh "$OUT"/*
