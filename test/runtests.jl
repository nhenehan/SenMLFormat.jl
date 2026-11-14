using SenMLFormat
using SHA
using Test

@testset "SenMLFormat" begin
    include("helpers.jl")
    include("fixtures.jl")
    include("core.jl")
    include("json.jl")
    include("cbor.jl")
    include("xml.jl")
    include("exi.jl")
    include("facade.jl")
    HAVE_RFC ? include("rfc_examples.jl") : @test_skip "RFC examples"
    include("shared_vectors.jl")
    include("robustness.jl")
    include("quality.jl")
end
