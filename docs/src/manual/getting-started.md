# Getting started

In this chapter you'll add SenMLFormat to a project and run the examples.

## Add SenMLFormat to your project

SenMLFormat needs Julia 1.10 or newer.

```julia
using Pkg
Pkg.add("SenMLFormat")
```

Then:

```julia
using SenMLFormat
```

This brings the data model into scope: `Record`, `Pack`, `validate`, `resolve`,
the media types and the rest. Each format is a module, `SenMLFormat.Json`,
`SenMLFormat.Cbor`, `SenMLFormat.Xml` and `SenMLFormat.Exi`, named so they don't
clash with the JSON.jl and XML.jl packages. `SenMLFormat.decode` and
`SenMLFormat.encode`, which pick the format by media type, are not exported
because the names are so common.

## Run the examples

The examples live in `examples/basics` of the repository, with their own
`Project.toml`:

```bash
git clone https://github.com/nhenehan/SenMLFormat.jl && cd SenMLFormat.jl
julia --project=examples/basics -e 'using Pkg; Pkg.develop(path=".")'   # once
julia --project=examples/basics examples/basics/first_pack.jl
julia --project=examples/basics examples/basics/run-all.jl              # every example
```

## The calls you'll use most

| Task | Call |
|---|---|
| Build a record | `Record(n = "room", u = "Cel", v = 21.5)` |
| Build a pack | `Pack([r1, r2])` |
| Write one format | `SenMLFormat.Json.encode(pack)` (also `Cbor`, `Xml`, `Exi`) |
| Read one format | `SenMLFormat.Json.decode(bytes)` |
| Pick the format at run time | `SenMLFormat.encode(media, pack)`, `SenMLFormat.decode(media, bytes)` |
| Check a pack | `validate(pack)` |
| Full names and times | `resolve(pack; now)` |

`decode` checks the pack as it reads, and `encode` checks it before writing. The
`_unchecked` versions skip that, for packs you know are valid.
