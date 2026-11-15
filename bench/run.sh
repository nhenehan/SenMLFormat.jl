#!/usr/bin/env bash
# SenMLFormat next to rsenml, timed the same way on the same data; writes
# docs/src/appendix/performance.md.
#
#   bench/run.sh            build bench/rsenml (rsenml v0.9.1 from GitHub), run
#                           both benchmarks, write docs/src/appendix/performance.md
#
# Env: SENML_JULIA  juliaup channel to time (default 1.12)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
CH="${SENML_JULIA:-1.12}"
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT

julia +"$CH" --startup-file=no --project=. bench/gen-data.jl
(cd bench/rsenml && cargo build --release --quiet)
# Three rounds, alternating; the report keeps each cell's fastest median, so a
# busy moment on the machine does not count against one side.
for _ in 1 2 3; do
    bench/rsenml/target/release/senml-jl-bench-rsenml bench/data >> "$OUT/rsenml.tsv"
    julia +"$CH" --startup-file=no --project=. bench/bench.jl bench/data >> "$OUT/senmlformat.tsv"
done
julia +"$CH" --startup-file=no bench/report.jl "$OUT/rsenml.tsv" "$OUT/senmlformat.tsv" > docs/src/appendix/performance.md
echo "wrote docs/src/appendix/performance.md"
