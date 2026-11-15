# SenMLFormat and rsenml compared

SenMLFormat is the Julia port of rsenml 0.9, and this compares only those two.
Speed is in [performance.md](performance.md), which `bench/run.sh` writes.

## Same results

SenMLFormat gives the same answers as rsenml, and the tests check it against
rsenml's own output (`test/fixtures/export`, written by rsenml's
`scripts/export-fixtures.sh`):

- the same verdict (accepted, or the same error kind) on all 66 of rsenml's
  conformance vectors;
- the same bytes in all eight media types and both EXI alignments for every test
  case and every accepted vector, and the same sizes on the benchmark data;
- the same EXI bytes as EXIficient 1.0.7 on all 32 streams;
- the same 25 conformance rows, with the same numbers ([conformance.md](conformance.md));
- the same 10 readings of unclear points of RFC 8428 ([Where the RFC is unclear](rfc-choices.md)).

## Features

| Feature | rsenml | SenMLFormat |
|---|---|---|
| JSON, CBOR, XML, EXI read and written | yes | yes |
| All 8 media types, CoAP Content-Formats | yes | yes |
| `decode` / `encode` / `encode_unchecked` by media type | yes | yes (`SenMLFormat.decode`, not exported) |
| Whole-pack `decode`, `decode_unchecked` | all formats | all formats |
| Record-by-record `RecordReader` | all formats | all formats |
| SenSML `StreamDecoder` (bytes as they arrive) | JSON, CBOR | JSON, CBOR |
| `StreamEncoder` (a record at a time) | all formats | all formats |
| Validation, with the registered-units option | yes | yes |
| Resolution (section 4.6) | yes | yes |
| Units registry, `rec=` fragments, base64url | yes | yes |
| EXI options: alignment, cookie, drop or refuse extensions, out-of-band options | yes | yes |
| Extensions kept through JSON and CBOR | yes | yes |
| Errors | `Error` enum with variants | one `SenMLError`; `kind` is the variant's name |
| Write into a fixed buffer (`encode_into`) | JSON, CBOR, XML, EXI | no (not needed in Julia; the JSON, CBOR and XML writers take any `IO`) |
| Zero-copy decoding (strings borrowed from the input) | CBOR, XML (`Cow`); JSON and EXI copy | no (records own their strings) |
| `no_std`, microcontroller builds, footprint measured | yes (Cortex-M) | not applicable |
| Optional formats | one Cargo feature per format | all four always loaded |
| Robustness testing | cargo-fuzz targets for every decoder, plus mutation tests | mutation tests (truncations and 64 random changes per input by default; set `SENML_MUTATIONS` for more); no coverage-guided fuzzing |
| Static checks | clippy, `forbid(unsafe_code)` | Aqua, JET |
| Package registry | not on crates.io (GitHub tag) | General registry (`Pkg.add("SenMLFormat")`) |
| Minimum toolchain | Rust 1.88 | Julia 1.10 |
| Dependencies | nanojson, minicbor, xmlparser, rexi | EXIFormat, PrecompileTools (own JSON, CBOR and XML readers) |
| Example | CoAP todo list with clients in four languages | `examples/basics` |

## Speed in short

See [performance.md](performance.md) for the tables. Measured on an AMD Ryzen 7
7840U with Julia 1.12.7 and rsenml v0.9.1:

| Operation | SenMLFormat / rsenml |
|---|---|
| decode (all formats) | about 2× to 4× slower |
| encode (all formats) | about 1.7× to 2.5× slower |
