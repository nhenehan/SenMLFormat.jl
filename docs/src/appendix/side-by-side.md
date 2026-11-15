# rsenml and SenMLFormat side by side

This page shows how each rsenml call looks in SenMLFormat, so you can move between
Rust and Julia.

[rsenml](https://github.com/nhenehan/rsenml) is the Rust version of SenMLFormat.
SenMLFormat takes its test vectors from rsenml's `fixtures/export`, writes the
same bytes in every format and gives the same verdicts. Its manual follows
[rsenml's guide](https://nhenehan.github.io/rsenml/) chapter for chapter, with the
same devices and data.

| Task | SenMLFormat (Julia) | rsenml (Rust) |
|---|---|---|
| Build a record | `Record(n = "room", v = 21.5)` | `Record::new().with_name("room").with_value(21.5)` |
| Build a pack | `Pack([r1, r2])` | `[r1, r2].into_iter().collect::<Pack>()` |
| Write JSON | `SenMLFormat.Json.encode(pack)` | `rsenml::json::encode(&pack)?` |
| Read CBOR | `SenMLFormat.Cbor.decode(bytes)` | `rsenml::cbor::decode(&bytes)?` |
| Byte-aligned EXI | `SenMLFormat.Exi.encode(pack; alignment = :byte_aligned)` | `exi::encode_with(&pack, &EncodeOptions::new().with_alignment(Alignment::ByteAligned))` |
| By media type | `SenMLFormat.encode(SENML_CBOR, pack)` | `rsenml::encode(MediaType::SenmlCbor, &pack)` |
| Check | `validate(pack)` | `pack.validate()` |
| Resolve | `resolve(pack; now)` | `pack.resolve(Some(now))` |
| Errors | `SenMLError`, with `kind` (`:MissingValue`, ...) | `Result` with `rsenml::Error` (`Error::MissingValue`, ...) |
| Record numbers in errors | from 1 | from 0 |

Only in rsenml: `no_std` and fixed buffers (`encode_into`).
