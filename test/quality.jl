# Package hygiene (Aqua) and type stability (JET). JET follows the Julia
# release closely; on a Julia it does not support yet, its tests are skipped.
using Aqua

@testset "Aqua" begin
    Aqua.test_all(SenMLFormat)
end

const JET_OK = try
    @eval using JET
    true
catch jet_error
    @warn "JET is not available on Julia $VERSION; skipping its tests" exception = jet_error
    false
end

if JET_OK
    @testset "JET" begin
        JET.test_package(SenMLFormat; target_modules = (SenMLFormat,))
    end
end
