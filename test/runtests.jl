using SenML
using SHA
using Test

@testset "SenML" begin
    include("fixtures.jl")
    include("core.jl")
    include("quality.jl")
end
