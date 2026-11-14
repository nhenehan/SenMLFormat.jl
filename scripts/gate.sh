#!/usr/bin/env bash
# Everything a commit must pass.
#
#   scripts/gate.sh           pins, fixtures, generated EXI tables, then the tests
#                             (with Aqua and JET) on the oldest supported Julia
#                             and the current one, then examples/basics
#   scripts/gate.sh --quick   tests on the current Julia only
#
# Env: SENML_JULIA_OLDEST   juliaup channel of the oldest Julia (default lts;
#                           it must be a 1.10.x)
#      SENML_JULIA_CURRENT  juliaup channel of the current Julia (default 1.12)
#      SENML_EXIFORMAT_PATH a local EXIFormat checkout (see scripts/dev-env.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
OLDEST="${SENML_JULIA_OLDEST:-lts}"
CURRENT="${SENML_JULIA_CURRENT:-1.12}"

QUICK=0
case "${1:-}" in
    --quick) QUICK=1 ;;
    "") ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

step() { echo; echo "== $*"; }

run_tests() { # channel
    # Manifests are not committed; each Julia resolves its own (JET's version
    # follows the Julia release) in a scratch environment.
    rm -f Manifest.toml test/Manifest.toml
    local env
    env="$(scripts/dev-env.sh "$1")"
    julia +"$1" --startup-file=no --project="$env" -e 'using Pkg; Pkg.test("SenMLFormat")'
}

if [[ $QUICK -eq 0 ]]; then
    export SENML_REQUIRE_STANDARDS=1
    step "third-party pins"
    scripts/fetch-third-party.sh --check
    step "standards (RFC text, fetched, not committed)"
    scripts/fetch-standards.sh --check
    step "fixtures"
    scripts/sync-fixtures.sh --check
    step "generated EXI tables"
    scripts/gen-tables.sh --check

    oldest_version="$(julia +"$OLDEST" --startup-file=no -e 'print(VERSION)')"
    [[ "$oldest_version" == 1.10.* ]] || {
        echo "juliaup channel '$OLDEST' is Julia $oldest_version, not 1.10.x (set SENML_JULIA_OLDEST)" >&2
        exit 1
    }
    step "tests on Julia $oldest_version ($OLDEST)"
    run_tests "$OLDEST"
fi

step "tests on Julia $(julia +"$CURRENT" --startup-file=no -e 'print(VERSION)') ($CURRENT)"
run_tests "$CURRENT"

if [[ $QUICK -eq 0 ]]; then
    step "example"
    env="$(scripts/dev-env.sh "$CURRENT")"
    julia +"$CURRENT" --startup-file=no --project="$env" examples/basics/basics.jl >/dev/null
fi

echo
echo "gate passed"
