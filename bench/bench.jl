# Times SenMLFormat on the datasets in data/ the way bench/rsenml times rsenml, and
# prints the same TSV lines: dataset, codec, operation, median ns of one call
# (or the size in bytes for "size").
using SenMLFormat

"""
Median time of one call: calls are batched so one sample lasts at least 200 µs;
51 samples after 20 warm-up calls (rsenml compare's `median_ns`).
"""
function median_ns(f)
    for _ in 1:20
        f()
    end
    batch = 1
    while true
        t = time_ns()
        for _ in 1:batch
            f()
        end
        (time_ns() - t >= 200_000 || batch >= 1 << 20) && break
        batch *= 2
    end
    samples = map(1:51) do _
        t = time_ns()
        for _ in 1:batch
            f()
        end
        (time_ns() - t) / batch
    end
    return sort!(samples)[26]
end

const SINK = Ref{Any}()

function main(dir)
    for set in ("rfc-5.1.3", "synthetic-200")
        text = read(joinpath(dir, set * ".json"))
        pack = SenMLFormat.Json.decode(text)
        line(codec, op, x) = println(set, '\t', codec, '\t', op, '\t', round(x; digits = 1))
        codecs = (
            ("JSON", SenMLFormat.Json.decode, SenMLFormat.Json.encode),
            ("CBOR", SenMLFormat.Cbor.decode, SenMLFormat.Cbor.encode),
            ("XML", SenMLFormat.Xml.decode, SenMLFormat.Xml.encode),
            ("EXI bit-packed", SenMLFormat.Exi.decode, p -> SenMLFormat.Exi.encode(p)),
            ("EXI byte-aligned", SenMLFormat.Exi.decode, p -> SenMLFormat.Exi.encode(p; alignment = :byte_aligned)),
        )
        for (name, dec, enc) in codecs
            b = enc(pack)
            line(name, "size", length(b))
            line(name, "decode", median_ns(() -> (SINK[] = dec(b))))
            line(name, "encode", median_ns(() -> (SINK[] = enc(pack))))
            if name == "JSON"
                line(name, "decode+resolve",
                    median_ns(() -> (SINK[] = length(resolve(SenMLFormat.Json.decode(b); now = 1.7e9)))))
            end
        end
    end
end

main(length(ARGS) >= 1 ? ARGS[1] : joinpath(@__DIR__, "data"))
