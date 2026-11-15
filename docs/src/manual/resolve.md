# Base fields and resolving

In this chapter you'll see how base fields and relative times work, and how to
turn records into full names and absolute times.

A home water meter reports its total use (a sum, in litres) every 10 minutes. The
first record sets the base name, base time, base unit and a base sum. The times
are relative to the base time:

```@setup resolve
#! setup resolve.jl
```

```@example resolve
#! include resolve.jl main
```

Resolving follows [RFC 8428 section 4.6](https://www.rfc-editor.org/rfc/rfc8428#section-4.6):

- **Name**: base name + name.
- **Unit**: the record's unit, else the base unit.
- **Time**: base time + time. A result below 2^28 is relative to "now", so it
  needs the `now` you pass in (seconds since 1970). Resolving a relative time
  without `now` throws a `SenMLError` of kind `:RelativeTime`.
- **Value**: base value + value, for numbers only.
- **Sum**: base sum + sum.
- The resolved records come out in time order.

A record can hold base fields and nothing else. It sets context for the records
after it and resolves to nothing.

## Record by record

[`resolve`](@ref) works on a whole pack. For a stream, use a [`Resolver`](@ref):
give it each record as it arrives with [`resolve!`](@ref), and change "now" with
[`set_now!`](@ref) when you need to.

## Picking records out

A [`RecordSelector`](@ref) reads the `rec=` fragment identifiers of
[section 9](https://www.rfc-editor.org/rfc/rfc8428#section-9), such as `rec=3-5`,
and [`selected`](@ref) tells you which positions they pick. A record's meaning
depends on the base fields before it, so resolve the whole pack first, then pick.
