# When things go wrong

In this chapter you'll see what the errors look like.

Everything that can go wrong throws one exception type, [`SenMLError`](@ref), in
every format:

```@setup errors
#! setup errors.jl
```

```@example errors
#! include errors.jl main
```

The message is for people; check `kind` in code. Each `kind` is named after
rsenml's matching `Error` variant, so the two libraries can be checked against
each other. Errors about one record say which one in `record`, counted from 1.

| `kind` | Meaning |
|---|---|
| `:Syntax` | The bytes are not valid JSON, CBOR, XML or EXI. `offset` gives the byte. |
| `:Incomplete` | The input ended too early. For a stream: wait for more bytes. |
| `:WrongType`, `:DuplicateLabel`, `:MultipleValues` | A record's fields are wrong. |
| `:MustUnderstand` | A label ending in `_` that SenMLFormat doesn't know. |
| `:InvalidLabel` | An extension uses a name the format keeps for a registered label. |
| `:InvalidBase64`, `:NonFinite` | A data value or a number that SenML can't carry. |
| `:EmptyPack`, `:MissingValue`, `:MissingName`, `:InvalidName` | The pack breaks a rule of section 4. |
| `:InvalidVersion`, `:UnsupportedVersion`, `:InconsistentVersion` | `bver` problems. |
| `:UnregisteredUnit` | Only with `registered_units = true`. |
| `:RelativeTime` | Resolving found a relative time, and no `now` was given. |
| `:Structure` | The XML or EXI root or record element is missing or wrong. |
| `:SchemaId` | The EXI stream doesn't name the RFC 8428 schema (`"a"`). |
| `:Unrepresentable` | The pack can't be written in this format. |
| `:Exi` | An error from the EXI codec that has no SenML meaning. |
