# Changelog

## Unreleased

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
