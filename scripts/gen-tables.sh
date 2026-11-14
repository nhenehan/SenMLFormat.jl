#!/usr/bin/env bash
# Regenerates the EXI grammar tables in src/generated with EXIFormat.SchemaGen.
#
#   scripts/gen-tables.sh           write them
#   scripts/gen-tables.sh --check   exit 1 if they are out of date
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# EXIFormat comes from a scratch environment (scripts/dev-env.sh).
ENV_DIR="$("$ROOT/scripts/dev-env.sh")"
exec julia --startup-file=no --project="$ENV_DIR" "$ROOT/scripts/gen-tables.jl" "$@"
