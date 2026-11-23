# SenMLFormat.jl

*SenML (RFC 8428) sensor readings for Julia: JSON, CBOR, XML and EXI from one data model.*

[![docs-stable](https://img.shields.io/badge/docs-stable-blue.svg)](https://nhenehan.github.io/SenMLFormat.jl/stable)
[![docs-dev](https://img.shields.io/badge/docs-dev-blue.svg)](https://nhenehan.github.io/SenMLFormat.jl/dev)
[![CI](https://github.com/nhenehan/SenMLFormat.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/nhenehan/SenMLFormat.jl/actions/workflows/CI.yml)
[![codecov](https://codecov.io/gh/nhenehan/SenMLFormat.jl/graph/badge.svg)](https://codecov.io/gh/nhenehan/SenMLFormat.jl)

SenMLFormat reads and writes sensor readings in Julia. The format is SenML (Sensor
Measurement Lists, [RFC 8428](https://www.rfc-editor.org/rfc/rfc8428)), a small
IETF standard: a list of records, each with a name, a value, and maybe a unit and
a time. A thermostat, a water meter and a web app can all agree on it without
sharing any code.

SenMLFormat is the Julia version of [rsenml](https://github.com/nhenehan/rsenml),
the way [EXIFormat](https://github.com/nhenehan/EXIFormat.jl) is the Julia version
of [rexi](https://github.com/nhenehan/rexi). It makes the same choices where the
RFC leaves room, and writes the same bytes in every format.

**Supported:** all four SenML formats (JSON, CBOR, XML and EXI) over one data
model, and SenSML, the streaming form.

## Installation

The package can be installed with Julia's package manager. In the Pkg REPL (press
`]` to enter it):

```
pkg> add SenMLFormat
```

or with Pkg functions: `using Pkg; Pkg.add("SenMLFormat")`. SenMLFormat needs
Julia 1.10 or newer, and brings in EXIFormat for EXI.

## Quick example

```julia
using SenMLFormat

# The cooling unit of a small smart office sends one pack per minute. The first
# record sets a base name (the unit) and a base time (Unix seconds) for all of
# them; every unit is from the RFC 8428 units registry.
pack = Pack([
    Record(bn = "urn:dev:mac:0024befffe804ff1:", bt = 1.7e9, n = "supply-air", u = "Cel", v = 12.8),
    Record(n = "return-air", u = "Cel", v = 24.1),
    Record(n = "room", u = "Cel", v = 22.6),
    Record(n = "humidity", u = "%RH", v = 48.0),
    Record(n = "setpoint", u = "Cel", v = 22.0),
    Record(n = "fan", u = "/", v = 0.65),
    Record(n = "compressor", vb = true),
])

# Write it in each format, then read it back.
for media in (SENML_JSON, SENML_CBOR, SENML_XML, SENML_EXI)
    bytes = SenMLFormat.encode(media, pack)
    @assert SenMLFormat.decode(media, bytes) == pack
    println(content_type(media), ": ", length(bytes), " bytes")
end

# Resolve the pack: full names and absolute times (RFC 8428 section 4.6).
for r in resolve(pack; now = 1_700_000_000)
    println(r.name, " = ", repr(r.value))
end
```

It prints:

```text
application/senml+json: 288 bytes
application/senml+cbor: 188 bytes
application/senml+xml: 355 bytes
application/senml-exi: 139 bytes
urn:dev:mac:0024befffe804ff1:supply-air = 12.8
urn:dev:mac:0024befffe804ff1:return-air = 24.1
urn:dev:mac:0024befffe804ff1:room = 22.6
urn:dev:mac:0024befffe804ff1:humidity = 48.0
urn:dev:mac:0024befffe804ff1:setpoint = 22.0
urn:dev:mac:0024befffe804ff1:fan = 0.65
urn:dev:mac:0024befffe804ff1:compressor = true
```

`SenMLFormat.decode` and `SenMLFormat.encode` are not exported, as the names are common.

## Learn more

- **[The documentation](https://nhenehan.github.io/SenMLFormat.jl/stable)** has a manual that works through one small
  example per idea, from a first pack to streaming, an API reference, and the
  choices made where the RFC is unclear.
- **[`examples/basics`](examples/basics)** contains the manual's scripts. Each
  has a Rust twin in rsenml's `examples/basics` with the same data.

## SenML implementation

| Feature | Status | Notes |
|---|---|---|
| JSON (`application/senml+json`) | Supported | |
| CBOR (`application/senml+cbor`) | Supported | Integer keys of Table 4; SenSML as an indefinite-length array |
| XML (`application/senml+xml`) | Supported | UTF-8 only; a DTD is refused |
| EXI (`application/senml-exi`) | Supported | Strict, with the section 8 schema, built on EXIFormat |
| EXI bit-packed and byte-aligned | Supported | Written with the options in the header (schemaId `"a"`); streams without them are read when you give the options |
| SenSML streams | Supported | All four media types |
| Reading a stream as bytes arrive | JSON and CBOR | XML and EXI read record by record from whole input |
| Validation | Supported | The rules of section 4; registered units on request |
| Resolving | Supported | Full names, absolute times, base values and sums (section 4.6) |
| Units registry | Supported | Table 6 of RFC 8428 |
| `rec=` fragment identifiers | Supported | Section 9.1 |
| CoAP Content-Formats | Supported | All eight media types |
| Extensions in EXI | Not supported | Strict EXI can't carry them: dropped by default, or refused |
| Non-strict EXI | Not supported | |
| XPointer fragment identifiers | Not supported | Section 9.2 |

One known limit: EXI cannot carry -0.0, so it is written as 0. The other choices,
and what is different in Julia, are in the docs'
[Where the RFC is unclear](https://nhenehan.github.io/SenMLFormat.jl/stable/appendix/rfc-choices/).

## Standards

| Standard | What it is | Implemented |
|---|---|---|
| [RFC 8428](https://www.rfc-editor.org/rfc/rfc8428) | SenML itself: the data model and the JSON, CBOR, XML and EXI formats | Yes |
| [RFC 9100](https://www.rfc-editor.org/rfc/rfc9100) | Updates RFC 8428: `bver` becomes a bitmap of features | No |
| [RFC 8798](https://www.rfc-editor.org/rfc/rfc8798) | More units for the SenML Units registry, and secondary units | No |
| [RFC 9193](https://www.rfc-editor.org/rfc/rfc9193) | Fields that give the Content-Format of a data value (`ct`, `ce`) | No |
| [RFC 8790](https://www.rfc-editor.org/rfc/rfc8790) | FETCH and PATCH of SenML records over CoAP | No |

[references.md](references.md) lists these and the other standards SenMLFormat
uses.

## Conformance and interoperability

Test results from the full test gate (`scripts/gate.sh`, on Julia 1.10 and 1.12).

| Test | Result |
|---|---|
| RFC 8428's JSON examples (sections 5.1.1 to 5.1.7) | All read and validate; 5.1.4 is 5.1.3 resolved |
| RFC 8428's CBOR dump (section 6) | Same bytes, both ways |
| RFC 8428's EXI dumps (section 8, bit-packed and byte-aligned) | Same bytes, both ways; Table 3's 161 bytes for 5.1.3 |
| rsenml's 66 conformance vectors | The same verdict on every one |
| rsenml's bytes, every vector and test case, all formats and both EXI alignments | The same bytes |
| EXI compared with EXIficient 1.0.7, 16 packs, both alignments | All 32 streams have the same bytes |
| Decoders on cut-off and randomly changed input | Only `SenMLError`, never another exception |

The test data comes from rsenml at a pinned tag (`fixtures/export`). The docs'
[comparison](https://nhenehan.github.io/SenMLFormat.jl/stable/appendix/comparison/) and
[performance](https://nhenehan.github.io/SenMLFormat.jl/stable/appendix/performance/) pages set the two side by side.

## Safe with untrusted data

A few hostile bytes can ask a decoder for a lot of work, such as an array of 2^64
records or endless nesting. SenMLFormat's decoders throw a `SenMLError` instead:
deep nesting stops at a fixed depth, huge announced lengths fail cleanly, and XML
DTDs (and so entity expansion) are refused. `decode` also validates the pack, so
what you get back follows RFC 8428's rules.

See the manual's [Untrusted input](https://nhenehan.github.io/SenMLFormat.jl/stable/manual/untrusted-input/) chapter.

## Thanks

- **Cullen Jennings, Zach Shelby, Jari Arkko, Ari Keränen and Carsten Bormann**
  wrote RFC 8428. Its examples, hex dumps and schema are the first tests
  SenMLFormat must pass.
- **Daniel Peintner** wrote [EXIficient](https://exificient.github.io/) with
  Richard Kuntschke at Siemens. SenMLFormat's EXI bytes are checked against
  EXIficient's.
- **Toralf Wittner** (minicbor), **Yevhenii Reizner** (xmlparser) and **Gronis**
  (nanojson) wrote the Rust parsers whose grammar rules SenMLFormat's readers
  follow.

Thank you.

## How this was made

SenMLFormat was written with the help of an AI coding tool (Claude Code),
working to my design and under my review. Every change has to pass the same
tests: the bytes must match rsenml in all four formats, EXI must match
EXIficient, and the test suite runs on Julia 1.10 and 1.12. I understand and
maintain the code, and I answer for it.

## License

BSD-3-Clause, the same as rsenml. See [LICENSE](LICENSE). The downloaded RFC keeps
its own license.

For the code layout, tests, test data and docs build, see
[CONTRIBUTING.md](CONTRIBUTING.md). Notes for AI coding agents are in
[AGENTS.md](AGENTS.md).
