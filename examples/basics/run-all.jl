# Runs every example, in the order the manual uses:
#     julia --project=examples/basics examples/basics/run-all.jl
# Each one runs in a fresh Julia, the same way you would run it by hand.
for name in ("first_pack", "formats", "resolve", "validate", "stream", "errors")
    println("=== ", name)
    run(`$(Base.julia_cmd()) --startup-file=no --project=$(@__DIR__) $(joinpath(@__DIR__, name * ".jl"))`)
end
