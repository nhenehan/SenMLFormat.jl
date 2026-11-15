# Formats

Each format is a module with the same shape: `decode` and `encode` for whole
packs (both validate; the `_unchecked` versions don't), `RecordReader` to read
record by record, and `StreamEncoder` to write record by record. JSON and CBOR
also have a `StreamDecoder` that takes bytes as they arrive.

## By media type

```@docs
SenMLFormat.decode
SenMLFormat.encode
SenMLFormat.encode_unchecked
```

## JSON

```@docs
SenMLFormat.Json
SenMLFormat.Json.decode
SenMLFormat.Json.decode_unchecked
SenMLFormat.Json.encode
SenMLFormat.Json.encode_unchecked
SenMLFormat.Json.encode_record
SenMLFormat.Json.RecordReader
SenMLFormat.Json.StreamEncoder
SenMLFormat.Json.StreamDecoder
```

## CBOR

```@docs
SenMLFormat.Cbor
SenMLFormat.Cbor.decode
SenMLFormat.Cbor.decode_sensml
SenMLFormat.Cbor.decode_unchecked
SenMLFormat.Cbor.encode
SenMLFormat.Cbor.encode_sensml
SenMLFormat.Cbor.encode_unchecked
SenMLFormat.Cbor.encode_record
SenMLFormat.Cbor.RecordReader
SenMLFormat.Cbor.StreamEncoder
SenMLFormat.Cbor.StreamDecoder
```

## XML

```@docs
SenMLFormat.Xml
SenMLFormat.Xml.decode
SenMLFormat.Xml.decode_unchecked
SenMLFormat.Xml.encode
SenMLFormat.Xml.encode_unchecked
SenMLFormat.Xml.encode_record
SenMLFormat.Xml.RecordReader
SenMLFormat.Xml.StreamEncoder
XML_NAMESPACE
```

## EXI

```@docs
SenMLFormat.Exi
SenMLFormat.Exi.decode
SenMLFormat.Exi.decode_unchecked
SenMLFormat.Exi.encode
SenMLFormat.Exi.encode_unchecked
SenMLFormat.Exi.RecordReader
SenMLFormat.Exi.StreamEncoder
EXI_SCHEMA_ID
```

## Reading and writing streams

Each format module has its own `next_record!`, `record!` and `finish!`, with the
same meaning in all four. `finish(reader)` ([`finish`](@ref)) checks the end of
the input.

```@docs
SenMLFormat.Json.next_record!
SenMLFormat.Json.record!
SenMLFormat.Json.finish!
SenMLFormat.Json.isfinished
SenMLFormat.Json.position
SenMLFormat.Cbor.next_record!
SenMLFormat.Cbor.record!
SenMLFormat.Cbor.finish!
SenMLFormat.Cbor.isfinished
SenMLFormat.Cbor.position
SenMLFormat.Xml.next_record!
SenMLFormat.Xml.record!
SenMLFormat.Xml.finish!
SenMLFormat.Exi.next_record!
SenMLFormat.Exi.record!
SenMLFormat.Exi.finish!
```
