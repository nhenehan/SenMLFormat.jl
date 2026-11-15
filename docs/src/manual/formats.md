# Choosing a format

In this chapter you'll write the same pack in every SenML media type and compare
their sizes.

```@setup formats
#! setup formats.jl
```

```@example formats
#! include formats.jl main
```

`SenMLFormat.encode` and `SenMLFormat.decode` take a [`MediaType`](@ref), so a
server can pick the format from a request's `Content-Type` header or CoAP
Content-Format option. [`media_type`](@ref) turns either into a `MediaType`, and
returns `nothing` for one it doesn't know.

## Which one to use

| Format | Good for |
|---|---|
| JSON | Web APIs and people reading logs. Every language can read it. |
| CBOR | Small devices and CoAP: compact, and simple to write. |
| XML | Systems that already speak XML. |
| EXI | The smallest messages, for networks where every byte counts. |

The SenSML media types mark the data as a stream. The bytes are the same as
SenML, except in CBOR, where SenSML uses an array with no length up front (one
byte more here), so the writer doesn't need to know how many records are coming.

## EXI options

SenML EXI is strict, schema-informed EXI with the schema of
[RFC 8428 section 8](https://www.rfc-editor.org/rfc/rfc8428#section-8).
SenMLFormat writes the header with its options (schema ID `"a"`), as the RFC asks,
so any EXI reader with that schema can read it. Keywords of
[`SenMLFormat.Exi.encode`](@ref):

- `alignment = :bit_packed` (the default) is the smallest; `:byte_aligned` puts
  every value on a byte boundary, so a simple sensor can fill in a template by
  hand, as the RFC's second section 8 example shows.
- `cookie = true` writes the `$EXI` cookie (the RFC advises against it over CoAP
  and HTTP).
- `extensions = :drop` (the default) leaves out extensions, which strict EXI has
  no place for; `:error` refuses a pack that has any.

[`SenMLFormat.Exi.decode`](@ref) takes `out_of_band` for streams whose header
leaves the options out.
