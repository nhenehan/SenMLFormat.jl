# SenMLFormat basics: build a pack, write it in every format, read it back,
# resolve it, and stream SenSML record by record.
#
#   julia --project=examples/basics -e 'using Pkg; Pkg.develop(path=".")'   # once, from a clone
#   julia --project=examples/basics examples/basics/basics.jl

using SenMLFormat

# The cooling unit of a small smart office sends one pack per minute. The first
# record sets a base name (the unit) and a base time (Unix seconds) for all of
# them; every unit is from the RFC 8428 units registry.
pack = Pack([
    Record(bn = "urn:dev:mac:0024befffe804ff1:", bt = 1.7e9, n = "supply-air", u = "Cel", v = 12.8),
    Record(n = "return-air", u = "Cel", v = 24.1),
    Record(n = "room", u = "Cel", v = 22.6),
    Record(n = "humidity", u = "%RH", v = 48.0),
    Record(n = "setpoint", u = "Cel", v = 22.0),
    Record(n = "fan", u = "/", v = 0.65),
    Record(n = "compressor", vb = true),
])

# Write it in each format, then read it back.
for media in (SENML_JSON, SENML_CBOR, SENML_XML, SENML_EXI)
    bytes = SenMLFormat.encode(media, pack)
    @assert SenMLFormat.decode(media, bytes) == pack
    println(content_type(media), ": ", length(bytes), " bytes")
end

# Resolve the pack: full names and absolute times (RFC 8428 section 4.6).
for r in resolve(pack; now = 1_700_000_000)
    println(r.name, " = ", repr(r.value), " at ", r.time)
end

# SenSML over CBOR: the reader gets each record as soon as its bytes arrive.
stream = SenMLFormat.encode(SENSML_CBOR, pack)
decoder = SenMLFormat.Cbor.StreamDecoder()
for chunk in Iterators.partition(stream, 8)
    push!(decoder, collect(chunk))
    while (r = SenMLFormat.Cbor.next_record!(decoder)) !== nothing
        println("streamed: ", r.n)
    end
end
SenMLFormat.Cbor.finish(decoder)

# Errors name what went wrong, the way rsenml's do.
try
    SenMLFormat.decode(SENML_JSON, """[{"n":"room","v":22.6,"v":22.7}]""")
catch e
    e isa SenMLError || rethrow()
    println("refused: ", e.kind)
end
