# SenML.jl

SenML (Sensor Measurement Lists, [RFC 8428](https://www.rfc-editor.org/rfc/rfc8428))
is a small, standard way for sensors to send readings: a list of records, each
with a name, a value, and maybe a unit and a time. SenML.jl reads and writes
SenML in Julia. It also handles SenSML, the streaming form of SenML.

SenML.jl is the Julia twin of [rsenml](https://github.com/nhenehan/rsenml), the
way [JExi](https://github.com/nhenehan/jexi) is the twin of rexi. It follows the
same reading of RFC 8428 and writes the same bytes as rsenml in every format.

**Supported:** all four SenML representations, JSON, CBOR, XML and EXI, over one
data model. EXI is SenML's XML form coded as EXI (Efficient XML Interchange), as
RFC 8428 section 8 describes, built on JExi.

## Quick example

```julia
using SenML

# A pack of two records. The first sets a base name for both.
pack = Pack([
    Record(bn = "urn:dev:ow:10e2073a01080063:", n = "temp", u = "Cel", v = 23.1),
    Record(n = "open", vb = false),
])

# Write it in each format, then read it back.
for media in (SENML_JSON, SENML_CBOR, SENML_XML, SENML_EXI)
    bytes = SenML.encode(media, pack)
    @assert SenML.decode(media, bytes) == pack
    println(content_type(media), ": ", length(bytes), " bytes")
end

# Resolve the pack: full names and absolute times (RFC 8428 section 4.6).
for r in resolve(pack; now = 1_700_000_000)
    println(r.name, " = ", repr(r.value))
end
```

It prints:

```text
application/senml+json: 93 bytes
application/senml+cbor: 63 bytes
application/senml+xml: 150 bytes
application/senml-exi: 55 bytes
urn:dev:ow:10e2073a01080063:temp = 23.1
urn:dev:ow:10e2073a01080063:open = false
```

`SenML.decode` and `SenML.encode` are not exported, as the names are common.

## One example per format

```julia
using SenML

# JSON (section 5)
pack = SenML.Json.decode("""[{"bn":"urn:dev:ow:10e2073a01080063:","n":"voltage","u":"V","v":120.1},
                             {"n":"current","u":"A","v":1.2}]""")
SenML.Json.encode(pack)        # the same JSON without whitespace

# CBOR (section 6): integer keys, numbers in their smallest exact form
cbor = SenML.Cbor.encode(pack)
SenML.Cbor.decode(cbor) == pack
SenML.Cbor.encode_sensml(pack)  # SenSML: an indefinite-length array

# XML (section 7)
xml = SenML.Xml.encode(pack)   # <sensml xmlns="urn:ietf:params:xml:ns:senml"><senml .../>...
SenML.Xml.decode(xml) == pack

# EXI (section 8): strict, schemaId "a", no cookie
exi = SenML.Exi.encode(pack)                               # bit-packed: the 63 bytes of section 8
SenML.Exi.encode(pack; alignment = :byte_aligned)          # byte-aligned
SenML.Exi.decode(exi) == pack
```

## Add to your project

SenML.jl is not in the General registry, and neither is JExi, which it uses for
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

Where the RFC is unclear, SenML.jl makes rsenml's choices; they and the
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
| `scripts/fetch-third-party.sh [--check \| --update NAME]` | the pinned rsenml in `~/.cache/senml.jl/third_party` |
| `scripts/fetch-standards.sh [--check]` | [RFC 8428](https://www.rfc-editor.org/rfc/rfc8428) from rfc-editor.org, and its section 8 XSD taken out of it, checked by sha256 (`standards.lock`), in `~/.cache/senml.jl/standards` |
| `scripts/sync-fixtures.sh [--check]` | rsenml's exported vectors and cases, the EXIficient streams |
| `scripts/gen-tables.sh [--check]` | EXI grammar tables of the [RFC 8428 section 8 XSD](https://www.rfc-editor.org/rfc/rfc8428#section-8) (JExi's schema compiler, schemaId "a") |
| `scripts/gate.sh [--quick]` | tests with Aqua and JET on Julia 1.11 and 1.12, the checks above, the example |
| `bench/run.sh` | SenML.jl and rsenml timed the same way on the same data |

## License

BSD 3-Clause, the same as rsenml. See [LICENSE](LICENSE). Standards are linked,
not committed; the downloaded RFC keeps its own license.
