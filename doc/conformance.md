# RFC 8428 conformance checklist

Each requirement, where SenMLFormat implements it, and the test that shows it. The
row numbers are those of
[rsenml's conformance.md](https://github.com/nhenehan/rsenml/blob/main/doc/conformance.md).
Tests are named `file` / testset. "All formats" means JSON, CBOR and XML read the
same way through one `RecordBuilder` (EXI's strict grammar cannot express most
violations in the first place).

| # | Requirement | RFC | Implementation | Tests |
|---|---|---|---|---|
| 1 | All labels of Tables 1, 2, 4, 5 with their types | 4.3, 5, 6, 7 | `src/core/label.jl` | `core.jl` / labels; `exi.jl` / every field and value type round trips; all-fields case in `shared_vectors.jl` |
| 2 | CBOR integer keys exactly as Table 4 | 6 | `src/core/label.jl` (CBOR keys) | `cbor.jl` / RFC 8428 section 6 both ways |
| 3 | Unknown labels ignored (kept as extensions) | 4.4 | `RecordBuilder` (`src/core/builder.jl`) | `json.jl` / unknown labels are kept or skipped; `cbor.jl` / unknown integer keys are ignored and text extensions kept |
| 3a | CBOR text key spelling a registered label (`"v"`) is an unrecognized field: ignored, value dropped | 4.4, 6, 12.2; RFC 9193 8 | `src/cbor.jl` | `cbor.jl` / text keys spelling registered labels are ignored |
| 4 | Unknown label ending in `_` is an error | 4.4 | `RecordBuilder` | `json.jl`, `cbor.jl` / record rules; `xml.jl` / XSD types |
| 5 | Version: positive integer, same in every record, newer than 10 refused; older accepted | 4.1, 4.4; RFC 9100 2-3 | `Validator` (`src/core/validate.jl`) | `core.jl` / validation; `json.jl` / record rules |
| 6 | Exactly one value unless a sum is present | 4.2 | `RecordBuilder`, `Validator` | `core.jl` / builder, validation |
| 7 | Name optional when a base name is present | 4.2 | `Validator` | `core.jl` / validation |
| 8 | Concatenated name character set and first character | 4.5.1 | `valid_name` | `core.jl` / validation, name rule matches the concatenation check |
| 9 | Unit falls back to base unit | 4.5.2 | `Resolver` (`src/core/resolve.jl`) | `core.jl` / resolution; `rfc_examples.jl` / 5.1.4 is 5.1.3 resolved |
| 10 | Time = bt + t; below 2^28 relative to now, else absolute | 4.5.3 | `Resolver`, `ABSOLUTE_TIME_THRESHOLD` | `rfc_examples.jl` / 5.1.7 actuation times |
| 11 | Sum = bs + s when either present; value = bv + v | 4.5.4 | `Resolver` | `core.jl` / resolution |
| 12 | Resolved records: no base fields, no relative times, chronological, `bver` only when not 10 | 4.6 | `resolve`, `to_record` | `rfc_examples.jl` / 5.1.4 is 5.1.3 resolved |
| 13 | Base values apply until the next record with the same base field | 4 | `Resolver` | `rfc_examples.jl` / 5.1.6 mixes base names |
| 14 | SenSML: records usable before the stream ends | 4.8 | `Json.StreamDecoder`, `Cbor.StreamDecoder` | `rfc_examples.jl` / the SenSML example streams record by record; `json.jl`, `cbor.jl` / stream decoder takes bytes as they come |
| 15 | JSON: UTF-8, RFC 8259 escapes, IEEE double range, lower-case `e` | 5 | `src/json.jl`; `write_number` (`src/core/number.jl`) | `json.jl` / escapes in strings and keys, JSON grammar is enforced, numbers keep their value in shortest form; `core.jl` / numbers |
| 16 | Data Value: unpadded base64url in JSON and XML, byte string in CBOR | 4.3, 5, 6, 7 | `src/core/base64url.jl`; CBOR byte strings | `core.jl` / base64url; `json.jl` / record rules; `xml.jl` / XSD types; `cbor.jl` / record rules |
| 17 | CBOR numbers convert back to the same double; `bver` unsigned only | 6 | `write_number`, CBOR reader | `cbor.jl` / numbers take the smallest exact form, every numeric form is read, record rules |
| 18 | CBOR: definite-length strings; definite array for SenML, indefinite for SenSML | 6 | `src/cbor.jl` | `cbor.jl` / SenSML uses an indefinite array, record rules; `facade.jl` / SenSML CBOR is an indefinite array |
| 19 | XML: UTF-8, namespace `urn:ietf:params:xml:ns:senml`, `sensml`/`senml` elements, Table 5 attributes | 7 | `src/xml.jl` | `xml.jl` / RFC 8428 section 7, namespaces, prefixes and foreign attributes, structure is enforced |
| 20 | EXI: strict schema mode with the RFC's XSD | 8 | `src/exi.jl`, the [RFC 8428 section 8 XSD](https://www.rfc-editor.org/rfc/rfc8428#section-8), `scripts/gen-tables.sh` | `exi.jl` / RFC 8428 section 8 both ways; the gate checks the generated tables |
| 21 | EXI header includes options with schemaId "a"; no cookie by default | 8 | `src/exi.jl` | `exi.jl` / schemaId is checked, cookie |
| 22 | EXI bit-packed and byte-aligned | 8 | `alignment` keyword | `exi.jl` / RFC 8428 section 8 both ways |
| 23 | Units registry | 12.1 | `src/core/units.jl` (Table 6), `Validator(registered_units = true)` | `core.jl` / units, validation |
| 24 | `rec=` fragment identifiers | 9 | `RecordSelector` (`src/core/fragment.jl`) | `core.jl` / fragments |
| 25 | Media types and CoAP Content-Formats | 12.3, 12.5 | `MediaType` (`src/core/media.jl`), `SenMLFormat.decode`/`encode` | `core.jl` / media types; `facade.jl` |

## The RFC's examples

All extracted at test time (`test/helpers.jl`) from the
[RFC 8428](https://www.rfc-editor.org/rfc/rfc8428) text that
`scripts/fetch-standards.sh` downloads:

| Vector | Result |
|---|---|
| JSON examples 5.1.1 - 5.1.7 (11 arrays) | all valid; 5.1.2's SenSML stream yields its records before the stream closes |
| 5.1.4 | equals 5.1.3 resolved |
| CBOR hex dump, section 6 | decoded = 5.1.2 (with its explicit `t: 0`); encoded byte for byte |
| XML, section 7 | decoded = 5.1.2 |
| EXI hex dump, section 8, bit-packed (63 bytes) | decoded = its XML; encoded byte for byte |
| EXI hex dump, section 8, byte-aligned | decoded = its XML; encoded byte for byte; the hand-coded sensor edit works |
| Table 3, EXI size of 5.1.3 | 161 bytes, as in the RFC |

## Beyond the RFC's examples

- **Same verdicts as rsenml.** All 66 of rsenml's conformance vectors (JSON, CBOR,
  SenSML CBOR; exported by rsenml's `scripts/export-fixtures.sh`) get rsenml's
  verdict, and the accepted ones the expected records (`shared_vectors.jl`).
- **Same bytes as rsenml.** For every accepted vector and all 16 test cases, JSON,
  CBOR, SenSML CBOR, XML and both EXI alignments equal rsenml's bytes
  (`shared_vectors.jl`); every case in all eight media types through
  `SenMLFormat.encode`, `SenMLFormat.encode_unchecked` and `SenMLFormat.decode` (`facade.jl`).
- **Same bytes as EXIficient.** All 32 EXIficient 1.0.7 streams (16 cases, two
  alignments), byte for byte (`exi.jl`).
- Every case round-trips through every format, and JSON -> CBOR -> XML -> EXI ->
  JSON gives the original JSON (`cbor.jl` / cross format).
- Only `SenMLError` escapes any decoder, on every truncation and on 64 random
  changes per input (`SENML_MUTATIONS=2000` for long runs) of every case in every
  format, fed to every decoder and both stream decoders; nor on deep nesting,
  oversized CBOR lengths or an XML entity bomb (`robustness.jl`, `json.jl`,
  `cbor.jl`, `xml.jl` / hostile input, entity expansion is refused).
