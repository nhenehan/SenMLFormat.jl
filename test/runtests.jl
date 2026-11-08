using SenML
using SHA
using Test

@testset "SenML" begin
    include("helpers.jl")
    include("fixtures.jl")
    include("core.jl")
    include("json.jl")
    include("rfc_examples.jl")
    include("shared_vectors.jl")
    include("robustness.jl")
    include("quality.jl")
end
