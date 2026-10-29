#!/bin/zsh
# Judges every command in the corpus with CommandRisk as it is at BEFORE (a commit) and as it is in this checkout,
# with the real models, and prints the table. Prints EVAL-DONE at the end, EVAL-FAILED on a failure.
#   OPENROUTER_API_KEY=… BEFORE=origin/main Tests/CommandApprovals/run.sh
# The older corpus (corpus.py) is at 17034a9:Tests/CommandApprovals/corpus.py; it's copied in beside these.
set -e
here=${0:A:h}; repo=${here:h:h}; work=$(mktemp -d)
git -C $repo show 17034a9:Tests/CommandApprovals/corpus.py > $work/corpus.py
cp $here/downloads.py $here/prep.py $here/summarize.py $work/
mkdir -p $work/before $work/after $work/results
git -C $repo show ${BEFORE:-origin/main}:Sources/Lamp/CommandRisk.swift > $work/before/CommandRisk.swift
cp $repo/Sources/Lamp/CommandRisk.swift $work/after/
for side in before after; do swiftc -O -o $work/eval-$side $here/stub.swift $work/$side/CommandRisk.swift $here/main.swift; done
python3 -I $work/prep.py $work
cd $work
for side in before after; do for name in downloads core generated; do
  echo "$(date +%T) $side $name"
  RUNS=5 RATING_RUNS=${RATING_RUNS:-3} ./eval-$side $name.json results/$side-$name.json || { echo EVAL-FAILED; exit 1; }
done; done
python3 -I summarize.py $work > results/summary.md && cat results/summary.md && echo "results in $work/results" && echo EVAL-DONE
