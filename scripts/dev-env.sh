#!/usr/bin/env bash
# Makes a scratch Julia environment with this checkout dev'd into it, and prints
# its folder. The gate, gen-tables.sh and the example run in it, so nothing here
# needs a committed path or [sources] entry.
#
#   scripts/dev-env.sh [CHANNEL]   CHANNEL is a juliaup channel (default: julia on PATH)
#
# Env: SENML_EXIFORMAT_PATH  a local EXIFormat checkout to use instead of the
#                            registered package (to try a change in both)
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHANNEL="${1:-}"
JULIA=(julia)
[[ -n "$CHANNEL" ]] && JULIA=(julia +"$CHANNEL")
ENV_DIR="$ROOT/.devenv/${CHANNEL:-default}"
rm -rf "$ENV_DIR"
mkdir -p "$ENV_DIR"
SENML_ROOT="$ROOT" ENV_DIR="$ENV_DIR" "${JULIA[@]}" --startup-file=no -e '
    using Pkg
    Pkg.activate(ENV["ENV_DIR"]; io = devnull)
    specs = [PackageSpec(path = ENV["SENML_ROOT"])]
    exif = get(ENV, "SENML_EXIFORMAT_PATH", "")
    isempty(exif) || pushfirst!(specs, PackageSpec(path = exif))
    Pkg.develop(specs; io = devnull)
    # gen-tables.jl loads EXIFormat itself, so the env needs it as a direct
    # dependency, not only through SenMLFormat.
    isempty(exif) && Pkg.add("EXIFormat"; io = devnull)' >&2
echo "$ENV_DIR"
