# rsenml's conformance vectors and test cases (test/fixtures/export, written by
# rsenml's scripts/export-fixtures.sh): SenMLFormat must give the same verdict for
# every vector, the expected records for every accepted one, and the same bytes
# as rsenml in every format it has.

# Records equal apart from extensions (the oracle's expected records have none).
function same_fields(a::Record, b::Record)
    return a.bn == b.bn && a.bt == b.bt && a.bu == b.bu && a.bv == b.bv && a.bs == b.bs &&
        a.bver == b.bver && a.n == b.n && a.u == b.u && SenMLFormat.same_value(a.value, b.value) &&
        a.s == b.s && a.t == b.t && a.ut == b.ut
end

const DECODERS = Dict{String,Function}(
    "json" => SenMLFormat.Json.decode,
    "cbor" => SenMLFormat.Cbor.decode,
    "cbor-sensml" => SenMLFormat.Cbor.decode_sensml,
)

const ENCODERS = Dict{String,Function}(
    "json" => SenMLFormat.Json.encode,
    "cbor" => SenMLFormat.Cbor.encode,
    "cbor_sensml" => SenMLFormat.Cbor.encode_sensml,
    "xml" => SenMLFormat.Xml.encode,
    "exi_bp" => p -> SenMLFormat.Exi.encode(p),
    "exi_ba" => p -> SenMLFormat.Exi.encode(p; alignment = :byte_aligned),
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
        want = SenMLFormat.Json.decode_unchecked(v["expected"])
        @test (v["id"], length(pack) == length(want) && all(same_fields.(pack, want))) == (v["id"], true)
        for (fmt, enc) in ENCODERS
            haskey(v, fmt) || continue  # vectors carry no SenSML CBOR column
            @test (v["id"], fmt, enc(pack)) == (v["id"], fmt, unhex(v[fmt]))
        end
    end
    @test tested == count(v -> haskey(DECODERS, v["fmt"]), vs)

    for c in cases()
        pack = SenMLFormat.Json.decode(unhex(c["json"]))
        for (fmt, enc) in ENCODERS
            @test (c["name"], fmt, enc(pack)) == (c["name"], fmt, unhex(c[fmt]))
        end
        # Every format reads back the same pack (EXI drops -0.0's sign).
        @test same_pack(SenMLFormat.Xml.decode(unhex(c["xml"])), pack)
        @test same_pack(SenMLFormat.Exi.decode(unhex(c["exi_bp"])), exi_view(pack))
        @test same_pack(SenMLFormat.Exi.decode(unhex(c["exi_ba"])), exi_view(pack))
        @test read(joinpath(FIXTURES, "exificient", c["name"] * ".xml")) == unhex(c["xml"])
    end
end
