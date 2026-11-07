#!/usr/bin/env bash
# Copy the test fixtures and the specs from the pinned rsenml checkout.
#
#   test/fixtures/export/      rsenml's conformance vectors and test cases, with
#                              its verdicts and bytes in every format (rsenml's
#                              scripts/export-fixtures.sh made them)
#   test/fixtures/exificient/  EXIficient 1.0.7 streams of every test case,
#                              verified against manifest.tsv
#   spec/                      RFC 8428 text and the section 7 XML schema
#
#   scripts/sync-fixtures.sh           copy
#   scripts/sync-fixtures.sh --check   exit 1 if anything differs from the pin
#                                      or a stream does not match its sha256
#
# Env: SENML_THIRD_PARTY  cache directory (see scripts/fetch-third-party.sh)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${SENML_THIRD_PARTY:-${XDG_CACHE_HOME:-$HOME/.cache}/senml.jl/third_party}"
RSENML="$DIR/rsenml"
# directory here -> directory in the rsenml checkout
COPIES=(
    "test/fixtures/export:crates/rsenml-tests/fixtures/export"
    "test/fixtures/exificient:crates/rsenml-tests/fixtures/exificient"
)
SPECS=(rfc8428.txt senml.xsd)

CHECK=0
case "${1:-}" in
    --check) CHECK=1 ;;
    "") ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
esac

# Every stream the manifest lists (<case>.<profile>.exi) must have its sha256.
verify() { # dir
    local st=0 name profile bytes sha rest
    while IFS=$'\t' read -r name profile bytes sha rest; do
        [[ "$name" == case ]] && continue
        if [[ "$(sha256sum "$1/$name.$profile.exi" | cut -d' ' -f1)" != "$sha" ]]; then
            echo "SHA      $name.$profile.exi" >&2
            st=1
        fi
    done <"$1/manifest.tsv"
    return $st
}

[[ -d "$RSENML" ]] || { echo "missing $RSENML; run scripts/fetch-third-party.sh" >&2; exit 1; }

if [[ $CHECK -eq 1 ]]; then
    st=0
    for c in "${COPIES[@]}"; do
        diff -r -q "$RSENML/${c#*:}" "$ROOT/${c%%:*}" >&2 || st=1
    done
    for f in "${SPECS[@]}"; do
        cmp -s "$RSENML/spec/$f" "$ROOT/spec/$f" || { echo "DIFFERS  spec/$f" >&2; st=1; }
    done
    verify "$ROOT/test/fixtures/exificient" || st=1
    [[ $st -eq 0 ]] && echo "fixtures ok"
    exit $st
fi

for c in "${COPIES[@]}"; do
    rm -rf "${ROOT:?}/${c%%:*}"
    mkdir -p "$ROOT/${c%%:*}"
    cp -a "$RSENML/${c#*:}/." "$ROOT/${c%%:*}/"
done
mkdir -p "$ROOT/spec"
for f in "${SPECS[@]}"; do
    cp "$RSENML/spec/$f" "$ROOT/spec/$f"
done
verify "$ROOT/test/fixtures/exificient"
echo "fixtures copied from $RSENML"
