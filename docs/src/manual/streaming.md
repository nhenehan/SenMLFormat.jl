# Streaming with SenSML

In this chapter you'll write records one at a time and read them back as their
bytes arrive.

A tank level sensor sends a reading every minute over a connection that stays
open. The writer doesn't know how many records there will be, and the reader
wants each one as soon as it comes:

```@setup stream
#! setup stream.jl
```

```@example stream
#! include stream.jl main
```

`push!` adds bytes, and `next_record!` returns a record once all of it has
arrived, or `nothing` to say "wait for more". Each record is checked as it comes
out, so a bad record is reported where it is, not at the end of the stream.

## What each format offers

| | JSON | CBOR | XML | EXI |
|---|---|---|---|---|
| `StreamEncoder` (write record by record) | yes | yes | yes | yes |
| `RecordReader` (read record by record, whole input) | yes | yes | yes | yes |
| `StreamDecoder` (read as bytes arrive) | yes | yes | no | no |

The JSON, CBOR and XML `StreamEncoder`s write to any `IO`; the CBOR one writes an
array with no length up front, as SenSML in CBOR should. The EXI `StreamEncoder`
returns its bytes from `finish!`.

`RecordReader` is for a whole message that you don't want to turn into a `Pack`
first, for example to look at each record and keep only some.
