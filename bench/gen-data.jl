# Writes the two datasets of rsenml's compare (compare/src/perf.rs) as JSON
# files that both benchmarks read:
#   data/rfc-5.1.3.json      the RFC 8428 section 5.1.3 example (rsenml's bytes,
#                            from test/fixtures/export/cases.tsv)
#   data/synthetic-200.json  200 records in resolved form: three numeric sensors
#                            with units and one boolean, 30 s apart from 1.7e9
using SenMLFormat

const HERE = @__DIR__

for line in eachline(joinpath(HERE, "..", "test", "fixtures", "export", "cases.tsv"))
    cells = split(line, '\t')
    cells[1] == "rfc-5.1.3" || continue
    write(joinpath(HERE, "data", "rfc-5.1.3.json"), hex2bytes(cells[2]))
end

kinds = (("temp", "Cel"), ("hum", "%RH"), ("pres", "Pa"))
records = map(0:199) do i
    t = 1_700_000_000.0 + i * 30.0
    if i % 4 == 3
        Record(n = "urn:dev:ow:10e2073a01080063:door", vb = i % 8 == 3, t = t)
    else
        n, u = kinds[i%4+1]
        Record(n = "urn:dev:ow:10e2073a01080063:$n", u = u, v = ((i * 37) % 1000) / 10.0, t = t)
    end
end
write(joinpath(HERE, "data", "synthetic-200.json"), SenMLFormat.Json.encode(Pack(records)))
