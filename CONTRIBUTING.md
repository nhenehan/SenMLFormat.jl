# Contributing to SenMLFormat

This document covers the code layout, the build and test commands, the test data
and the docs build.

## Layout

| rsenml crate | SenMLFormat |
|---|---|
| `rsenml-core` | `src/core/*.jl`, one file per rsenml module |
| `rsenml-json` | `src/json.jl`, module `SenMLFormat.Json` |
| `rsenml-cbor` | `src/cbor.jl`, module `SenMLFormat.Cbor` |
| `rsenml-xml` | `src/xml.jl`, module `SenMLFormat.Xml` |
| `rsenml-exi` + `generated/senml.rs` | `src/exi.jl`, module `SenMLFormat.Exi` + `src/generated/senml_tables.jl` |
| `rsenml` (facade) | `src/facade.jl`: `SenMLFormat.decode`, `encode`, `encode_unchecked` |
| `rsenml-tests` | `test/` |

The docs page [Where the RFC is unclear](https://nhenehan.github.io/SenMLFormat.jl/stable/appendix/rfc-choices/) lists
the readings shared with rsenml and what is different in Julia.

## Gate and commands

```sh
scripts/fetch-third-party.sh   # the pinned rsenml, in a cache outside this tree
scripts/fetch-standards.sh     # download RFC 8428 (the tests read its examples)
scripts/sync-fixtures.sh       # copy rsenml's test data into test/fixtures
scripts/gate.sh                # everything a commit must pass (--quick: one Julia)
bench/run.sh                   # speed next to rsenml (needs cargo)
```

| Script | Purpose |
|---|---|
| `scripts/fetch-third-party.sh [--check \| --update NAME]` | The pinned rsenml in `~/.cache/senmlformat/third_party` |
| `scripts/fetch-standards.sh [--check]` | [RFC 8428](https://www.rfc-editor.org/rfc/rfc8428) and its section 8 XSD, checked by sha256 (`standards.lock`), in `~/.cache/senmlformat/standards` |
| `scripts/sync-fixtures.sh [--check]` | rsenml's exported vectors and cases, and the EXIficient streams |
| `scripts/gen-tables.sh [--check]` | EXI grammar tables of the section 8 XSD (EXIFormat's schema compiler, schemaId "a") |
| `scripts/gate.sh [--quick]` | Tests with Aqua and JET on Julia 1.10 and 1.12, the checks above, the examples |
| `bench/run.sh` | SenMLFormat and rsenml timed the same way; writes `docs/src/appendix/performance.md` |

The gate runs in a scratch environment made by `scripts/dev-env.sh`. Set
`SENML_EXIFORMAT_PATH` to a local EXIFormat checkout to test a change in both.
The oldest Julia is the juliaup channel in `SENML_JULIA_OLDEST` (default `lts`).

Without the downloaded RFC, `Pkg.test("SenMLFormat")` skips the tests that read
it, with a warning. The gate sets `SENML_REQUIRE_STANDARDS`, which makes them
required.

## Test data from rsenml

`test/fixtures/export` holds rsenml's conformance vectors and test cases, with
rsenml's verdicts and bytes, at the rsenml tag pinned in `third-party.lock`.
`test/fixtures/exificient` holds the EXIficient 1.0.7 streams. Change them only
with `scripts/sync-fixtures.sh` after moving the pin. Behaviour changes go into
rsenml first, then come here.

## Docs

The documentation is built with [Documenter.jl](https://documenter.juliadocs.org/)
from `docs/`, and published to https://nhenehan.github.io/SenMLFormat.jl: `/dev` from `main`, `/stable` from the
latest version tag. The `docs` job of `.github/workflows/CI.yml` builds and
deploys it.

```sh
julia --project=docs -e 'using Pkg; Pkg.instantiate()'   # once
julia --project=docs docs/make.jl                        # writes docs/build
```

- `docs/src/manual` holds the chapters. Their code comes from the scripts in
  `examples/basics`: a fenced block holding `#! include first_pack.jl main`
  gets that script's `# ANCHOR: main` region, and `#! setup first_pack.jl` the
  script's `using` lines, for a hidden `@setup` block. Documenter runs the
  `@example` blocks, so the pages always show the scripts' real output. Never
  paste code or output into a page.
- `docs/src/api` lists the public names in `@docs` blocks. The build fails when
  an exported name is missing there, has no docstring, or a cross-reference does
  not resolve.
- `docs/src/appendix/comparison.md` and `performance.md` come from
  `bench/run.sh`; don't edit the numbers by hand.
- Deploying needs the `DOCUMENTER_KEY` secret and its deploy key (made once with
  `DocumenterTools.genkeys`).

## Releasing

SenMLFormat is in Julia's General registry. Bump `version` in `Project.toml`,
add a CHANGELOG section, run the full gate, push, then comment
`@JuliaRegistrator register` on the commit. After the registry merges it,
TagBot tags the version, and the tag builds `/stable`.
