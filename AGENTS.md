# AGENTS.md

## About this project

SenMLFormat reads and writes SenML and SenSML ([RFC 8428](https://www.rfc-editor.org/rfc/rfc8428)) in Julia: JSON, CBOR, XML and EXI over one data model. It is the Julia twin of [rsenml](https://github.com/nhenehan/rsenml), the Rust library, and must write the same bytes and give the same verdicts. EXI goes through [EXIFormat](https://github.com/nhenehan/EXIFormat.jl).

Use the parts it already has rather than adding another parser or data model.

## Module layout

| If you need to... | Look in | rsenml crate it matches |
|---|---|---|
| Records, packs, validation, resolution, units, `rec=` fragments, media types, base64url, number text | `src/core/*.jl` (one file per rsenml module) | `rsenml-core` |
| JSON (section 5) | `src/json.jl`, `SenMLFormat.Json` | `rsenml-json` |
| CBOR (section 6) | `src/cbor.jl`, `SenMLFormat.Cbor` | `rsenml-cbor` |
| XML (section 7) | `src/xml.jl`, `SenMLFormat.Xml` | `rsenml-xml` |
| EXI (section 8) | `src/exi.jl`, `SenMLFormat.Exi`, and `src/generated/senml_tables.jl` | `rsenml-exi` |
| One call for any media type | `src/facade.jl`: `SenMLFormat.decode`, `encode`, `encode_unchecked` (not exported) | `rsenml` |

Do not add JSON.jl, CBOR.jl or XML.jl. Each reader here copies the grammar rules of the Rust crate rsenml uses (nanojson, minicbor, xmlparser), quirks included, so both libraries give the same verdict on the same bytes. The docs page `docs/src/appendix/rfc-choices.md` explains each choice.

## Choosing an interface

- Whole packs: `decode` / `encode` in the format module, or the facade with a `MediaType`.
- One record at a time: `RecordReader` to read, `StreamEncoder` to write.
- Bytes as they arrive (SenSML over JSON or CBOR): `StreamDecoder`, `next_record!`, `finish`.
- `decode` validates; `decode_unchecked` and `encode_unchecked` skip the checks.
- EXI keywords: `alignment` (`:bit_packed` or `:byte_aligned`), `cookie`, `extensions` (`:drop` or `:error`), and `out_of_band` for streams without options.

## Generated tables

`src/generated/senml_tables.jl` holds the EXI grammar tables of the RFC 8428 section 8 schema, with schemaId "a". `scripts/gen-tables.sh` makes it with EXIFormat's schema compiler. Never edit it by hand; regenerate it, and the gate checks it with `--check`.

## EXI rules

Strict EXI, as section 8 says: the options in the header with schemaId "a", or agreed out of band; bit-packed or byte-aligned; no cookie by default. EXI cannot carry -0.0, so it is written as 0. Report only what the tests show: the two section 8 examples, Table 3's 161-byte size, and the 32 EXIficient streams.

## Errors

Every decoder throws only `SenMLError`, on any input. Its `kind` is a `Symbol` named after rsenml's matching error variant. Do not add a kind rsenml does not have, and do not loosen a check to make a test pass.

## Security

Treat every input as untrusted. Do not remove or weaken:

- the JSON nesting limit for unknown labels (`MAX_DEPTH = 32`, `src/json.jl`);
- the CBOR length checks against the remaining input;
- the XML DTD refusal (so there is no entity expansion), and UTF-8 only;
- the robustness tests (`test/robustness.jl`: truncations and random changes, `SENML_MUTATIONS` for more).

Changes to any of these need tests.

## Interoperability

The bytes must equal rsenml's in all eight media types and both EXI alignments, and the verdicts must equal rsenml's on its 66 test vectors (`test/shared_vectors.jl`, `test/facade.jl`).

`test/fixtures/export` and `test/fixtures/exificient` come only from the rsenml version pinned in `third-party.lock`, copied by `scripts/sync-fixtures.sh`. Never edit them here. A change in behaviour goes into rsenml first, then into the fixtures, then here.

## Development conventions

Do not invent functions, keyword arguments or error kinds; check the source first. Follow rsenml's reading of the unclear points (`docs/src/appendix/rfc-choices.md`, "The same readings"). Write comments in plain, everyday words, and link the RFC section (`https://www.rfc-editor.org/rfc/rfc8428#section-...`) where code follows it.

## Testing

The steps are in `CONTRIBUTING.md`. In short:

1. `scripts/fetch-third-party.sh` and `scripts/fetch-standards.sh`, once.
2. `scripts/gate.sh` before every commit: the third-party pin, the standards, `scripts/sync-fixtures.sh --check`, `scripts/gen-tables.sh --check`, then `Pkg.test` with Aqua and JET on Julia 1.10 and 1.12, then `examples/basics`. `--quick` runs only the tests on the current Julia.
3. The gate and `gen-tables.sh` run in a scratch environment made by `scripts/dev-env.sh`. Set `SENML_EXIFORMAT_PATH` to a local EXIFormat checkout to test against it.

Check the gate's exit status itself; do not pipe it through `grep` and read the output.

## Documentation

The docs are built with Documenter.jl from `docs/` (`julia --project=docs docs/make.jl`). Update the manual (`docs/src/manual`) when a public function or user-facing behaviour changes, and list every exported name in the API reference (`docs/src/api`); the build fails otherwise. Manual pages take their code from `examples/basics` with `#! include` lines (see `docs/make.jl`), and Documenter runs it: never paste code or output into them. The manual follows rsenml's guide chapter for chapter, with the same data; keep them in step.

`docs/src/appendix/performance.md` is written only by `bench/run.sh` (it needs cargo); do not edit it by hand. Keep the README's "It prints" block the same as what `examples/basics/basics.jl` prints. Development steps go in `CONTRIBUTING.md`, not the README.

## Repository rules

- Never commit `CR.md` (change requests are instructions, not project files), `Manifest.toml`, third-party code, or RFC text and schemas. The RFC is fetched by `scripts/fetch-standards.sh` and checked by `standards.lock`.
- Third-party checkouts and the downloaded RFC live in `~/.cache/senmlformat`, never in the working tree.
