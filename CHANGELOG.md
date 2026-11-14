# Changelog

## Unreleased

First release. SenMLFormat reads and writes SenML and SenSML
([RFC 8428](https://www.rfc-editor.org/rfc/rfc8428)) in all four formats. It is
the Julia twin of [rsenml](https://github.com/nhenehan/rsenml) and writes the
same bytes as rsenml in every format.

- **Core** (sections 4, 9 and 12): `Record` (keyword constructor), `Extension`
  and `Pack`; validation (`validate`, `Validator`); resolution (`resolve`,
  `Resolver`, `ResolvedRecord`); the units registry of Table 6; `rec=` fragment
  identifiers (`RecordSelector`); the media types and their CoAP Content-Format
  numbers; strict unpadded base64url; the shortest text for every number, equal
  to rsenml's. Every error is one `SenMLError`, whose `kind` names rsenml's
  matching error.
- **Facade**: `SenMLFormat.decode(media, input)`, `SenMLFormat.encode(media, pack)`
  and `SenMLFormat.encode_unchecked(media, pack)` for all eight media types (not
  exported, as the names are common).
- **JSON** (`SenMLFormat.Json`, section 5): `decode`, `decode_unchecked`,
  `encode`, `encode_unchecked`, `RecordReader`, and a SenSML `StreamDecoder` and
  `StreamEncoder`. Every rsenml JSON test vector gets the same verdict.
- **CBOR** (`SenMLFormat.Cbor`, section 6): the same functions plus
  `decode_sensml` and `encode_sensml`. Integers, half, single and double floats
  and tag 4 decimal fractions are read; numbers are written in their smallest
  exact form. The RFC's section 6 example comes out byte for byte, both ways.
- **XML** (`SenMLFormat.Xml`, section 7): `decode`, `decode_unchecked`, `encode`,
  `encode_unchecked`, `RecordReader`, `StreamEncoder`. UTF-8 only; DTDs are
  refused.
- **EXI** (`SenMLFormat.Exi`, section 8), on
  [EXIFormat](https://github.com/nhenehan/EXIFormat.jl): `decode` (with
  `out_of_band` for streams without options), `decode_unchecked`, `encode` and
  `encode_unchecked` (`alignment`, `cookie`, `extensions`), `RecordReader`,
  `StreamEncoder`. Both section 8 examples come out byte for byte, both ways, and
  all 32 EXIficient 1.0.7 test streams match. EXI cannot carry -0.0, which is
  written as 0.
- **Checked against rsenml**: the same bytes and verdicts on rsenml's 64 test
  vectors and 16 test cases in every media type; truncated and randomly changed
  input only ever gives a `SenMLError`.
- `examples/basics`, `doc/design.md` (the reading of unclear points),
  `doc/conformance.md` (a requirement-by-requirement checklist),
  `doc/comparison.md` and `doc/performance.md` (next to rsenml).
