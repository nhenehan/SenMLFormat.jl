# Writes doc/performance.md from the TSV output of bench/rsenml and bench/bench.jl.
# Each file may hold several rounds; the fastest median of each cell is used.
#   julia bench/report.jl rsenml.tsv senml.jl.tsv
using Printf

function load(path)
    d = Dict{Tuple{String,String,String},Float64}()
    for l in eachline(path)
        isempty(l) && continue
        set, codec, op, x = split(l, '\t')
        d[(set, codec, op)] = min(get(d, (set, codec, op), Inf), parse(Float64, x))
    end
    return d
end

rs, jl = load(ARGS[1]), load(ARGS[2])
cmd(c) = try strip(read(c, String)) catch; "unknown" end
cpu = let m = match(r"model name\s*:\s*(.*)", read("/proc/cpuinfo", String)); m === nothing ? "unknown" : m[1] end

const SETS = ("rfc-5.1.3" => "RFC 5.1.3 (22 records)", "synthetic-200" => "synthetic 200")
const CODECS = ("JSON", "CBOR", "XML", "EXI bit-packed", "EXI byte-aligned")
us(x) = @sprintf("%.1f", x / 1000)
ratio(a, b) = @sprintf("%.1f×", b / a)

println("""
# SenML.jl and rsenml: performance

Written by `bench/run.sh`; do not edit by hand.

SenML.jl is compared with rsenml only. Both read the same JSON files
(`bench/data`): the RFC 8428 section 5.1.3 example and the 200-record synthetic
pack of rsenml's `compare` (resolved records: three numeric sensors and a door
switch, 30 s apart). Both are timed the same way (`median_ns` of rsenml's
`compare/src/perf.rs`): calls batched to at least 200 µs, the median of 51
batches after 20 warm-up calls. `bench/run.sh` runs both three times, taking
turns, and keeps the fastest median of each cell. Decoders validate and encoders validate first,
as `decode` and `encode` do. "decode+resolve" is JSON decode, then resolution with
a given "now".

- CPU: $cpu
- Julia: $(cmd(`julia +$(get(ENV, "SENML_JULIA", "1.12")) --startup-file=no -e 'print(VERSION)'`)) (default flags)
- rsenml: v0.9.1, $(cmd(`rustc --version`)), release profile with LTO, one codegen unit
""")

println("## Sizes in bytes\n")
println("| Codec | ", join(last.(SETS), " | "), " |")
println("|---|", repeat("---:|", length(SETS)))
for c in CODECS
    cells = map(first.(SETS)) do s
        a, b = rs[(s, c, "size")], jl[(s, c, "size")]
        a == b ? string(Int(a), " (equal)") : string(Int(b), " vs rsenml ", Int(a))
    end
    println("| $c | ", join(cells, " | "), " |")
end

for (s, title) in SETS
    println("\n## $title: time per call in µs\n")
    println("| Codec | Operation | rsenml | SenML.jl | SenML.jl / rsenml |")
    println("|---|---|---:|---:|---:|")
    for c in CODECS, op in ("decode", "encode", "decode+resolve")
        haskey(rs, (s, c, op)) || continue
        a, b = rs[(s, c, op)], jl[(s, c, op)]
        println("| $c | $op | ", us(a), " | ", us(b), " | ", ratio(a, b), " |")
    end
end
