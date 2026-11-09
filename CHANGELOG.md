# Changelog

## Unreleased

- **Standards are linked, not committed**: `spec/` is gone.
  `scripts/fetch-standards.sh` downloads RFC 8428 from rfc-editor.org into
  `~/.cache/senml.jl/standards` and takes the section 8 XSD out of it, both
  checked by sha256 against `standards.lock`; the tests and `gen-tables.sh` read
  them there, and the gate checks them. `sync-fixtures.sh` no longer copies them
  from rsenml.
- **Measured next to rsenml**: `bench/` times SenML.jl and rsenml v0.9.1 the
  same way on rsenml compare's datasets (`bench/run.sh` writes
  `doc/performance.md`); `doc/comparison.md` compares features. Sizes are equal
  in every format.
- **Faster encoding and validation**: the writers (JSON, CBOR, XML, EXI) and the
  finite-number check no longer loop over tuples of fields of mixed types, which
  boxed every field. Encoding is 5-12× faster (1.7-2.5× rsenml's time, from
  10-25×); decoding, which validates, 2× faster.
- **Facade**: `SenML.decode(media, input)`, `SenML.encode(media, pack)` and
  `SenML.encode_unchecked(media, pack)` for all eight media types (not exported).
  Every test case in every media type equals rsenml's bytes. README with one
  example per format, `doc/design.md`, `doc/conformance.md` (rsenml's row
  numbers), a PrecompileTools workload, and `examples/basics` (run by the gate).
- **EXI** (`SenML.Exi`, RFC 8428 section 8) on JExi 0.2 (`[sources]`, tag
  `v0.2.0`): `decode` (with `out_of_band` for streams without options),
  `decode_unchecked`, `encode` and `encode_unchecked` (`alignment`, `cookie`,
  `extensions`), `RecordReader`, `StreamEncoder`. Grammar tables generated from
  the [RFC 8428 section 8 XSD](https://www.rfc-editor.org/rfc/rfc8428#section-8) with schemaId "a" (`scripts/gen-tables.sh`, checked by the
  gate). Both section 8 dumps both ways; all 32 EXIficient streams byte for
  byte; -0.0 is written as 0.
- **XML** (`SenML.Xml`, RFC 8428 section 7): `decode`, `decode_unchecked`,
  `encode`, `encode_unchecked`, `RecordReader`, `StreamEncoder`. Its own
  tokenizer with xmlparser's rules (names, characters, comments, CDATA, the
  declaration); UTF-8 only, DTDs refused; namespaces, references and
  attribute-value normalization; the XSD types of Table 5. Output equals rsenml's
  bytes for every test case. No XML.jl dependency.
- **CBOR** (`SenML.Cbor`, RFC 8428 section 6): `decode`, `decode_unchecked`,
  `decode_sensml`, `encode`, `encode_unchecked`, `encode_sensml`, `RecordReader`,
  SenSML `StreamDecoder` and `StreamEncoder`. Integers, half/single/double floats
  and tag 4 decimal fractions are read; numbers are written in the smallest exact
  form. The section 6 dump both ways; every rsenml CBOR vector gets the same
  verdict and bytes.
- **JSON** (`SenML.Json`, RFC 8428 section 5): `decode`, `decode_unchecked`,
  `encode`, `encode_unchecked`, `RecordReader`, SenSML `StreamDecoder` and
  `StreamEncoder`. Its own reader with nanojson's grammar rules, so every rsenml
  JSON vector gets the same verdict; output equals rsenml's bytes for every
  vector and test case.
- **Core** (RFC 8428 section 4 and 9, 12): `Record` (keyword constructor),
  `Extension`, `Pack`; validation (`validate`, `Validator`); resolution (`resolve`,
  `Resolver`, `ResolvedRecord`); the units registry; `rec=` fragments
  (`RecordSelector`); media types and CoAP Content-Formats; strict unpadded
  base64url; shortest number text equal to rsenml's (Rust's tie rule included);
  one `SenMLError` type whose `kind` names rsenml's error variants.
- Repository scaffold: package, gate, third-party pin of rsenml, and the test
  fixtures copied from it.
