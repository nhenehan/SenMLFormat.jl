# Where the RFC is unclear

SenMLFormat is a port of rsenml 0.9 (its fixtures come from rsenml 0.9.2). Its rules, its reading of the unclear points
of RFC 8428 and its output bytes are rsenml's; see
[Where the RFC is unclear](https://nhenehan.github.io/rsenml/rfc-choices.html)
in rsenml's guide, and its
[CONTRIBUTING.md](https://github.com/nhenehan/rsenml/blob/main/CONTRIBUTING.md),
for the reasons behind them. This page lists those choices in short, then what is
different because this is Julia.

## Layout

| rsenml crate | SenMLFormat |
|---|---|
| `rsenml-core` | `src/core/*.jl`, one file per rsenml module |
| `rsenml-json` | `src/json.jl`, module `SenMLFormat.Json` |
| `rsenml-cbor` | `src/cbor.jl`, module `SenMLFormat.Cbor` |
| `rsenml-xml` | `src/xml.jl`, module `SenMLFormat.Xml` |
| `rsenml-exi` + `generated/senml.rs` | `src/exi.jl`, module `SenMLFormat.Exi` + `src/generated/senml_tables.jl` |
| `rsenml` (facade) | `src/facade.jl`: `SenMLFormat.decode`, `SenMLFormat.encode`, `SenMLFormat.encode_unchecked` |
| `rsenml-tests` | `test/` |

The format modules are `Json`, `Cbor`, `Xml` and `Exi`, not `JSON` or `XML`,
so they do not clash with the JSON.jl and XML.jl packages in a user's code.

## The same readings as rsenml

1. **Records of base fields only.** A record with no regular field at all (like
   the first record of section 5.1.7) is context for the records after it: it needs
   no value or name and resolves to nothing. Every other record needs a value or a
   sum (section 4.2).
2. **Version.** A record's version is the last `bver` at or before it (default
   10); it must be the same in every record; newer than 10 is refused, older is
   accepted (the RFC's own example has `bver: 5`).
3. **Names** (4.5.1): base name + name must match `[A-Za-z0-9][A-Za-z0-9:./_-]*`.
4. **Resolution** (4.6): `bv` adds to numeric values only; sum is `bs + s` when
   either is present; relative times need the caller's `now`; unknown base
   extensions are dropped, regular ones kept; output sorted by time (stable).
5. **Units** need not be registered; `Validator(registered_units = true)` makes it
   a rule. The registry is Table 6 only.
6. **Numbers** must be finite in every format.
7. **Data values** are strict unpadded base64url.
8. **CBOR keys.** A text key that spells a registered label is an unknown field,
   ignored with its value. Strings must be definite-length. SenML packs are
   definite arrays; SenSML streams may be indefinite and are written so.
9. **XML.** UTF-8 only; a DTD is refused; comments, processing instructions and
   whitespace are allowed between records; attributes in other namespaces are
   ignored; `bver` is `xs:int`.
10. **EXI.** Options with schemaId "a" in the header; streams without options only
    with `out_of_band`; extensions dropped (or refused with `extensions = :error`);
    **-0.0 is written as 0**, as EXI has no negative zero.

Writers put fields in the order bn bt bu bv bs bver n u t ut s v vs vb vd, then
extensions, without whitespace. Numbers use the shortest text that reads back as
the same double; CBOR numbers take the smallest exact form.

## What is different in Julia

- **Records.** `Record` is immutable, built with keywords
  (`Record(n = "temp", v = 23.1)`); each field is `nothing` when absent. Its
  value is one field `value::Union{Nothing,Value}` with
  `Value = Union{Float64,String,Bool,Vector{UInt8}}`; the `v`, `vs`, `vb` and `vd`
  keywords pick the kind. Records compare by kind, so `vb = true` is not `v = 1`
  (in Julia `true == 1.0`). `Pack` is an `AbstractVector{Record}`. Records are
  numbered from 1 in errors; byte offsets count from 0, like rsenml's.
- **Errors.** One exception type, `SenMLError`. Its `kind` is a `Symbol` named
  after rsenml's `Error` variant (`:Syntax`, `:MissingValue`, ...), so a test can
  check that both libraries give the same verdict. The decoders throw nothing else,
  on any input.
- **JSON, CBOR and XML readers written here.** rsenml uses nanojson, minicbor and
  xmlparser. SenMLFormat does not use JSON.jl, CBOR.jl or XML.jl: each reader is
  written here with the grammar rules of the Rust crate it stands for, quirks
  included (for example a value cut off inside a CBOR map is `:Syntax`, as in
  minicbor, not `:Incomplete`), so the 66 shared vectors get the same verdict.
  XML.jl is not used: it gives no error offsets and accepts input xmlparser
  refuses.
- **Shortest numbers.** Julia's `repr(Float64)` is Ryu, like Rust's, but Rust
  rounds exact halfway cases up and Julia does not; `shortest()` applies Rust's
  rule. Checked equal to Rust on 300 000 doubles.
- **EXI through EXIFormat.** EXIFormat 0.2 is a hard dependency, from the
  General registry. The grammar tables are made by EXIFormat's schema compiler from
  the [RFC 8428 section 8 XSD](https://www.rfc-editor.org/rfc/rfc8428#section-8) with schemaId "a" (`scripts/gen-tables.sh`) and committed. The
  RFC is not committed: `scripts/fetch-standards.sh` downloads it and takes the
  schema out of it.
  EXIFormat errors become `SenMLError`s.
- **Not ported:** `encode_into` (rsenml's fixed-buffer writers, for `no_std`).
  In Julia, `encode` returns a new `Vector{UInt8}`. The JSON, CBOR and XML
  per-record writers (`encode_record`, `StreamEncoder`) write to any `IO`; EXI's
  `StreamEncoder` returns the bytes from `finish!`. The `no_std` and footprint
  work does not apply.
- **Facade names.** `SenMLFormat.decode`, `SenMLFormat.encode` and `SenMLFormat.encode_unchecked`
  are not exported (common names). They take bytes or a string.
- **Precompiling.** A PrecompileTools workload reads and writes a small pack in all
  eight media types, so the first call in a new session is quick.
