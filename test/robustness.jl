# Decoders never fail with anything but a SenMLError: valid encodings of every
# case, cut at every length and randomly changed, go through every decoder (each
# format's input through every other decoder too). SENML_MUTATIONS sets the
# changes per input (default 64).

# xorshift64*, deterministic.
mutable struct Rng
    s::UInt64
end
function next!(r::Rng)
    r.s ⊻= r.s >> 12
    r.s ⊻= r.s << 25
    r.s ⊻= r.s >> 27
    return r.s * 0x2545f4914f6cdd1d
end
below(r::Rng, n::Integer) = Int(next!(r) % UInt64(max(n, 1)))

function mutate(rng::Rng, input::Vector{UInt8})
    out = copy(input)
    for _ in 0:below(rng, 3)
        k = below(rng, 4)
        if k == 0 && !isempty(out)
            i = below(rng, length(out)) + 1
            out[i] ⊻= UInt8(1) << below(rng, 8)
        elseif k == 1 && !isempty(out)
            out[below(rng, length(out))+1] = next!(rng) % UInt8
        elseif k == 2
            insert!(out, below(rng, length(out) + 1) + 1, next!(rng) % UInt8)
        elseif !isempty(out)
            deleteat!(out, below(rng, length(out)) + 1)
        end
    end
    return out
end

function decode_everything(input::Vector{UInt8})
    for f in values(DECODERS)
        try
            f(input)
        catch e
            e isa SenMLError || return (e, f)
        end
    end
    d = SenML.Json.StreamDecoder()
    try
        for i in 1:7:length(input)
            push!(d, input[i:min(i + 6, end)])
            while SenML.Json.next_record!(d) !== nothing
            end
        end
        SenML.Json.finish(d)
    catch e
        e isa SenMLError || return (e, "Json.StreamDecoder")
    end
    return nothing
end

@testset "robustness" begin
    mutations = parse(Int, get(ENV, "SENML_MUTATIONS", "64"))
    rng = Rng(0x9e3779b97f4a7c15)
    failures = Any[]
    for c in cases()
        for (fmt, enc) in ENCODERS
            bytes = unhex(c[fmt])
            step = max(length(bytes) ÷ 200, 1)
            for len in 0:step:(length(bytes)-1)
                f = decode_everything(bytes[1:len])
                f === nothing || push!(failures, (c["name"], fmt, "cut", len, f))
            end
            for _ in 1:mutations
                m = mutate(rng, bytes)
                f = decode_everything(m)
                f === nothing || push!(failures, (c["name"], fmt, bytes2hex(m), f))
            end
        end
    end
    for v in vectors()
        f = decode_everything(unhex(v["input"]))
        f === nothing || push!(failures, (v["id"], f))
    end
    isempty(failures) || foreach(println, first(failures, 5))
    @test isempty(failures)
end
