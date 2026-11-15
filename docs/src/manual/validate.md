# Checking packs

In this chapter you'll see what the RFC's rules refuse, and how to ask for more.

An HVAC unit reports its supply air temperature, its compressor, and its fan:

```@setup validate
#! setup validate.jl
```

```@example validate
#! include validate.jl main
```

`decode` runs the same checks while it reads, and `encode` runs them before it
writes, so you only call [`validate`](@ref) yourself for packs you build or change.
Records are counted from 1 in errors.

## The rules

These come from [RFC 8428 section 4](https://www.rfc-editor.org/rfc/rfc8428#section-4):

- A pack has at least one record.
- A record has a value or a sum, unless it holds only base fields.
- Each record has at most one value (`v`, `vs`, `vb` or `vd`), and each label at
  most once.
- A record needs a name or a base name, and the full name must be a valid name.
- Numbers must be finite (no NaN or infinity).
- The version (`bver`) must be a positive integer, the same in every record, and
  not newer than 10.
- A label that ends in `_` and that SenMLFormat does not know is refused.

## Units

RFC 8428 does not require registered units, so `"RPM"` passes by default.
`registered_units = true` only allows the units of the SenML Units registry
(Table 6 of [section 12.1](https://www.rfc-editor.org/rfc/rfc8428#section-12.1)).
[`lookup_unit`](@ref) tells you what a unit means.

The registry in SenMLFormat is RFC 8428's Table 6. The units added later by
RFC 8798 are not in it yet.

## Checking a stream

For records that arrive one at a time, a [`Validator`](@ref) checks each record
with [`check!`](@ref), and [`finish`](@ref) checks the end of the pack.
