# SenMLFormat

SenML (Sensor Measurement Lists, [RFC 8428](https://www.rfc-editor.org/rfc/rfc8428))
is a small, standard way for sensors to send readings: a list of records, each
with a name, a value, and maybe a unit and a time. SenMLFormat reads and writes
SenML in Julia. It also handles SenSML, the streaming form of SenML.

SenMLFormat is the Julia twin of [rsenml](https://github.com/nhenehan/rsenml), the
way [EXIFormat](https://github.com/nhenehan/jexi) is the twin of rexi. It follows the
same reading of RFC 8428 and writes the same bytes as rsenml in every format.

**Supported:** all four SenML representations, JSON, CBOR, XML and EXI, over one
data model. EXI is SenML's XML form coded as EXI (Efficient XML Interchange), as
RFC 8428 section 8 describes, built on EXIFormat.

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

## One example per format

```julia
using SenMLFormat

# JSON (section 5). This is the first example of RFC 8428 section 5.1.2
# (https://www.rfc-editor.org/rfc/rfc8428#section-5.1.2), which the RFC's EXI
# dump in section 8 also encodes.
pack = SenMLFormat.Json.decode("""[{"bn":"urn:dev:ow:10e2073a01080063:","n":"voltage","u":"V","v":120.1},
                             {"n":"current","u":"A","v":1.2}]""")
SenMLFormat.Json.encode(pack)        # the same JSON without whitespace

# CBOR (section 6): integer keys, numbers in their smallest exact form
cbor = SenMLFormat.Cbor.encode(pack)
SenMLFormat.Cbor.decode(cbor) == pack
SenMLFormat.Cbor.encode_sensml(pack)  # SenSML: an indefinite-length array

# XML (section 7)
xml = SenMLFormat.Xml.encode(pack)   # <sensml xmlns="urn:ietf:params:xml:ns:senml"><senml .../>...
SenMLFormat.Xml.decode(xml) == pack

# EXI (section 8): strict, schemaId "a", no cookie
exi = SenMLFormat.Exi.encode(pack)                               # bit-packed: the 63 bytes of section 8
SenMLFormat.Exi.encode(pack; alignment = :byte_aligned)          # byte-aligned
SenMLFormat.Exi.decode(exi) == pack
```

## Add to your project

SenMLFormat is not in the General registry, and neither is EXIFormat, which it uses for
EXI. Add both from GitHub (Julia 1.11 or newer):

```julia
using Pkg
Pkg.add(url = "https://github.com/nhenehan/jexi", rev = "v0.2.0")
Pkg.add(url = "https://github.com/nhenehan/senml.jl")
```

## What it does

- Reads and writes all eight SenML media types: `application/senml+json`,
  `senml+cbor`, `senml+xml`, `senml-exi`, and their SenSML twins. It also knows
  their CoAP Content-Format numbers (`media_type`, `coap_content_format`).
- Reads whole packs (`decode`) or one record at a time (`RecordReader`). Writes
  whole packs (`encode`) or one record at a time (`StreamEncoder`). JSON and CBOR
  can also read SenSML streams as the bytes arrive (`StreamDecoder`).
- Checks packs against the RFC's rules (`validate`), and resolves them into full
  names and absolute times (`resolve`).
- Includes the RFC 8428 units registry (`lookup_unit`) and `rec=` fragment
  identifiers (`RecordSelector`).
- Matches the RFC byte for byte. Its CBOR example and both EXI examples
  (bit-packed and byte-aligned) come out exactly the same, in both directions.
- Writes the same bytes as rsenml in every format, and the same EXI bytes as
  EXIficient 1.0.7, on every test case.
- Throws only `SenMLError` on cut-off or changed input. Its `kind` is the name
  of rsenml's matching error.

Where the RFC is unclear, SenMLFormat makes rsenml's choices; they and the
Julia-specific points are in [doc/design.md](doc/design.md). One known limit: EXI
cannot carry -0.0. The requirement-by-requirement checklist is
[doc/conformance.md](doc/conformance.md). How it compares with rsenml, features and
speed, is in [doc/comparison.md](doc/comparison.md) and
[doc/performance.md](doc/performance.md).

## Examples

- [`examples/basics`](examples/basics/basics.jl): the example above, plus a SenSML
  stream read in chunks and an error.

## Development

```sh
scripts/fetch-third-party.sh   # the pinned rsenml, in a cache outside this tree
scripts/fetch-standards.sh     # download RFC 8428 (the tests read its examples)
scripts/sync-fixtures.sh       # copy rsenml's test data into test/fixtures
scripts/gate.sh                # everything a commit must pass (--quick: one Julia)
bench/run.sh                   # speed next to rsenml (needs cargo), writes doc/performance.md
```

| Script | Purpose |
|---|---|
| `scripts/fetch-third-party.sh [--check \| --update NAME]` | the pinned rsenml in `~/.cache/senmlformat/third_party` |
| `scripts/fetch-standards.sh [--check]` | [RFC 8428](https://www.rfc-editor.org/rfc/rfc8428) from rfc-editor.org, and its section 8 XSD taken out of it, checked by sha256 (`standards.lock`), in `~/.cache/senmlformat/standards` |
| `scripts/sync-fixtures.sh [--check]` | rsenml's exported vectors and cases, the EXIficient streams |
| `scripts/gen-tables.sh [--check]` | EXI grammar tables of the [RFC 8428 section 8 XSD](https://www.rfc-editor.org/rfc/rfc8428#section-8) (EXIFormat's schema compiler, schemaId "a") |
| `scripts/gate.sh [--quick]` | tests with Aqua and JET on Julia 1.11 and 1.12, the checks above, the example |
| `bench/run.sh` | SenMLFormat and rsenml timed the same way on the same data |

## License

BSD 3-Clause, the same as rsenml. See [LICENSE](LICENSE). Standards are linked,
not committed; the downloaded RFC keeps its own license.
