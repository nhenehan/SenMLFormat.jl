# A tank level sensor sends SenSML: records go out one at a time, and the reader
# uses each one as soon as its bytes arrive.
#
# Rust version: rsenml/examples/basics/src/bin/stream.rs.

using SenMLFormat

# ANCHOR: main
# The sensor writes one record each minute into the same stream.
wire = IOBuffer()
encoder = SenMLFormat.Json.StreamEncoder()
SenMLFormat.Json.record!(encoder, wire,
    Record(bn = "urn:dev:mac:0024befffe804ff4:tank:", bt = 1_700_000_000,
           n = "level", u = "m", v = 1.82))
for (minute, level) in ((1, 1.81), (2, 1.79))
    SenMLFormat.Json.record!(encoder, wire, Record(n = "level", t = minute * 60, v = level))
end
SenMLFormat.Json.finish!(encoder, wire)
bytes = take!(wire)
println(String(copy(bytes)))

# The reader gets the bytes in pieces of 16, as a network might deliver them.
decoder = SenMLFormat.Json.StreamDecoder()
for piece in Iterators.partition(bytes, 16)
    push!(decoder, collect(piece))
    while (record = SenMLFormat.Json.next_record!(decoder)) !== nothing
        println("got ", record.n, " = ", repr(record.value))
    end
end
SenMLFormat.Json.finish(decoder)
println("stream finished: ", SenMLFormat.Json.isfinished(decoder))
# ANCHOR_END: main
