# SenML.jl

Sensor Measurement Lists ([RFC 8428](https://www.rfc-editor.org/rfc/rfc8428)) for
Julia: records and packs, read and written as JSON, CBOR, XML and EXI, plus SenSML
streams.

SenML.jl is the Julia twin of [rsenml](https://github.com/nhenehan/rsenml), the
way [JExi](https://github.com/nhenehan/jexi) is the twin of rexi. It follows the
same reading of RFC 8428 and writes the same bytes as rsenml in every format.

**Status:** under construction. Nothing works yet.

Needs Julia 1.11 or newer.

## Development

```sh
scripts/fetch-third-party.sh   # the pinned rsenml, in a cache outside this tree
scripts/sync-fixtures.sh       # copy its test data into test/fixtures and spec/
scripts/gate.sh                # everything a commit must pass (--quick: one Julia)
```

## License

BSD 3-Clause, the same as rsenml. See [LICENSE](LICENSE).
