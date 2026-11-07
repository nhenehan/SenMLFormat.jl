# The test data copied from rsenml (scripts/sync-fixtures.sh), and helpers to read it.
#
# export/vectors.tsv   rsenml's conformance vectors, with rsenml's verdict and bytes
# export/cases.tsv     rsenml's bytes for every test case in every format
# exificient/          EXIficient 1.0.7 streams of the same cases

const FIXTURES = joinpath(@__DIR__, "fixtures")

unhex(s::AbstractString) = hex2bytes(s)

"""
    read_tsv(path) -> Vector{Dict{String,String}}

Reads a TSV file with a header line. Cells hold no tabs or newlines.
"""
function read_tsv(path::AbstractString)
    lines = filter(!isempty, readlines(path))
    header = split(lines[1], '\t')
    return [Dict(String(k) => String(v) for (k, v) in zip(header, split(l, '\t'))) for l in lines[2:end]]
end

vectors() = read_tsv(joinpath(FIXTURES, "export", "vectors.tsv"))
cases() = read_tsv(joinpath(FIXTURES, "export", "cases.tsv"))
exificient_manifest() = read_tsv(joinpath(FIXTURES, "exificient", "manifest.tsv"))

@testset "fixtures" begin
    vs = vectors()
    @test length(vs) == 64
    @test all(v -> length(v) == 14, vs)
    @test all(v -> v["fmt"] in ("json", "cbor", "cbor-sensml"), vs)
    @test all(v -> v["expect"] in ("accept", "reject"), vs)
    # rsenml gives the expected outcome for every vector.
    @test all(v -> (v["rsenml"] == "ok") == (v["expect"] == "accept"), vs)

    cs = cases()
    @test length(cs) == 16
    @test all(c -> length(c) == 7, cs)

    m = exificient_manifest()
    @test length(m) == 2 * length(cs)
    for row in m
        bytes = read(joinpath(FIXTURES, "exificient", "$(row["case"]).$(row["profile"]).exi"))
        @test length(bytes) == parse(Int, row["bytes"])
        @test bytes2hex(sha256(bytes)) == row["sha256"]
    end
end
