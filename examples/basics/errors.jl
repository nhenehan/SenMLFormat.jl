# What decoding errors look like.
#
# Rust version: rsenml/examples/basics/src/bin/errors.rs.

using SenMLFormat

# ANCHOR: main
inputs = [
    "cut off" => """[{"n":"urn:dev:mac:0024befffe804ff1:room","v":21""",
    "two values" => """[{"n":"urn:dev:mac:0024befffe804ff1:room","v":21,"vb":true}]""",
    "bad name" => """[{"n":"room temp","v":21}]""",
    "newer version" => """[{"bver":11,"n":"urn:dev:mac:0024befffe804ff1:room","v":21}]""",
]
for (what, input) in inputs
    try
        pack = SenMLFormat.Json.decode(input)
        println(what, ": ok, ", length(pack), " records")
    catch e
        e isa SenMLError || rethrow()
        println(what, ": ", sprint(showerror, e))
        println("    kind = ", e.kind)
    end
end
# ANCHOR_END: main
