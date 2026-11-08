# SenML.jl basics: build a pack, write it in every format, read it back,
# resolve it, and stream SenSML record by record.
#
#   julia --project=examples/basics -e 'using Pkg; Pkg.instantiate()'
#   julia --project=examples/basics examples/basics/basics.jl

using SenML

# A pack of two records. The first sets a base name for both.
pack = Pack([
    Record(bn = "urn:dev:ow:10e2073a01080063:", n = "temp", u = "Cel", v = 23.1),
    Record(n = "open", vb = false),
])

# Write it in each format, then read it back.
for media in (SENML_JSON, SENML_CBOR, SENML_XML, SENML_EXI)
    bytes = SenML.encode(media, pack)
    @assert SenML.decode(media, bytes) == pack
    println(content_type(media), ": ", length(bytes), " bytes")
end

# Resolve the pack: full names and absolute times (RFC 8428 section 4.6).
for r in resolve(pack; now = 1_700_000_000)
    println(r.name, " = ", repr(r.value), " at ", r.time)
end

# SenSML over CBOR: the reader gets each record as soon as its bytes arrive.
stream = SenML.encode(SENSML_CBOR, pack)
decoder = SenML.Cbor.StreamDecoder()
for chunk in Iterators.partition(stream, 8)
    push!(decoder, collect(chunk))
    while (r = SenML.Cbor.next_record!(decoder)) !== nothing
        println("streamed: ", r.n)
    end
end
SenML.Cbor.finish(decoder)

# Errors name what went wrong, the way rsenml's do.
try
    SenML.decode(SENML_JSON, """[{"n":"temp","v":1,"v":2}]""")
catch e
    e isa SenMLError || rethrow()
    println("refused: ", e.kind)
end
