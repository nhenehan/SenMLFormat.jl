# Package hygiene (Aqua) and type stability (JET). JET follows the Julia
# release closely; on a Julia it does not support yet, its tests are skipped.
using Aqua

@testset "Aqua" begin
    Aqua.test_all(SenML)
end

const JET_OK = try
    @eval using JET
    true
catch err
    @warn "JET is not available on Julia $VERSION; skipping its tests" err
    false
end

if JET_OK
    @testset "JET" begin
        JET.test_package(SenML; target_modules = (SenML,))
    end
end
