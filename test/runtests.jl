using SenML
using SHA
using Test

@testset "SenML" begin
    include("fixtures.jl")
    include("quality.jl")
end
