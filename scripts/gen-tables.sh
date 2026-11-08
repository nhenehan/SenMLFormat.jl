#!/usr/bin/env bash
# Regenerates the EXI grammar tables in src/generated with JExi.SchemaGen.
#
#   scripts/gen-tables.sh           write them
#   scripts/gen-tables.sh --check   exit 1 if they are out of date
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec julia --startup-file=no --project="$ROOT" "$ROOT/scripts/gen-tables.jl" "$@"
