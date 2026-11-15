# Words you'll see

This page explains the SenML words the manual uses, so you can come back to it
when one is new.

## Record

One entry in a SenML list. It can hold a name (`n`), a unit (`u`), a value, a sum
(`s`), a time (`t`) and an update time (`ut`). The value is a number (`v`), a
string (`vs`), a boolean (`vb`) or bytes (`vd`). In SenMLFormat it is a
[`Record`](@ref).

## Pack

The whole list of records, sent as one message. In SenMLFormat it is a
[`Pack`](@ref), an `AbstractVector{Record}`.

## Base field

A field whose name starts with `b`: base name (`bn`), base time (`bt`), base unit
(`bu`), base value (`bv`), base sum (`bs`) and base version (`bver`). It applies to
its own record and to every record after it, until another record sets it again.
This saves repeating a long device name or a time in every record.

## Resolving

Turning records with base fields and relative times into self-contained ones: a
full name, a unit, an absolute time, and the base value or sum added in
([RFC 8428 section 4.6](https://www.rfc-editor.org/rfc/rfc8428#section-4.6)).
[`resolve`](@ref) gives [`ResolvedRecord`](@ref)s.

## Relative time

A time below 2^28 seconds (about 8.5 years) is counted from "now", the moment the
pack is read. Larger times are seconds since 1970 (UTC).

## SenSML

Sensor Measurement Streams: the same records, sent as a stream that may never end
([section 4.8](https://www.rfc-editor.org/rfc/rfc8428#section-4.8)). The reader
uses each record as soon as it arrives.

## Media type

The name that tells the receiver which format the bytes are in, such as
`application/senml+json`. SenML has eight: four formats, each as SenML and SenSML.
In SenMLFormat it is a [`MediaType`](@ref).

## Content-Format

The number CoAP uses instead of a media type name. `application/senml+cbor` is
112.

## EXI

Efficient XML Interchange: a W3C standard that sends XML as compact binary. SenML
EXI is SenML's XML form coded with the schema of
[section 8](https://www.rfc-editor.org/rfc/rfc8428#section-8). SenMLFormat uses
[EXIFormat](https://github.com/nhenehan/EXIFormat.jl) for it.

## Extension

A label the RFC does not define. Readers keep it if they can and otherwise ignore
it. A label that ends in `_` must be understood, so a reader that doesn't know it
refuses the pack.
