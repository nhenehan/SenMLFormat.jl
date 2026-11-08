# rsenml's conformance vectors and test cases (test/fixtures/export, written by
# rsenml's scripts/export-fixtures.sh): SenML.jl must give the same verdict for
# every vector, the expected records for every accepted one, and the same bytes
# as rsenml in every format it has.

# Records equal apart from extensions (the oracle's expected records have none).
function same_fields(a::Record, b::Record)
    return a.bn == b.bn && a.bt == b.bt && a.bu == b.bu && a.bv == b.bv && a.bs == b.bs &&
        a.bver == b.bver && a.n == b.n && a.u == b.u && SenML.same_value(a.value, b.value) &&
        a.s == b.s && a.t == b.t && a.ut == b.ut
end

const DECODERS = Dict{String,Function}(
    "json" => SenML.Json.decode,
)

const ENCODERS = Dict{String,Function}(
    "json" => SenML.Json.encode,
)

@testset "shared vectors" begin
    vs = vectors()
    tested = 0
    for v in vs
        haskey(DECODERS, v["fmt"]) || continue
        tested += 1
        input = unhex(v["input"])
        got = Ref{Any}(nothing)
        verdict = errkind(() -> (got[] = DECODERS[v["fmt"]](input)))
        @test (v["id"], verdict) == (v["id"], Symbol(v["rsenml"]))
        verdict === :ok || continue
        pack = got[]
        want = SenML.Json.decode_unchecked(v["expected"])
        @test (v["id"], length(pack) == length(want) && all(same_fields.(pack, want))) == (v["id"], true)
        for (fmt, enc) in ENCODERS
            @test (v["id"], fmt, enc(pack)) == (v["id"], fmt, unhex(v[fmt]))
        end
    end
    @test tested == count(v -> haskey(DECODERS, v["fmt"]), vs)

    for c in cases()
        pack = SenML.Json.decode(unhex(c["json"]))
        for (fmt, enc) in ENCODERS
            @test (c["name"], fmt, enc(pack)) == (c["name"], fmt, unhex(c[fmt]))
        end
    end
end
