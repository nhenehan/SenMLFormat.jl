# A pack of three readings from a room thermostat, written as JSON and read back.
#
# Rust version: rsenml/examples/basics/src/bin/first_pack.rs.

using SenMLFormat

# ANCHOR: main
# The first record sets a base name, a base time and a base unit. The records
# after it use them too.
pack = Pack([
    Record(bn = "urn:dev:mac:0024befffe804ff1:", bt = 1_700_000_000, bu = "Cel",
           n = "room", v = 21.5),
    Record(n = "setpoint", v = 21.0),
    Record(n = "heating", u = "/", v = 0.4),
])

json = SenMLFormat.Json.encode(pack)
println(String(copy(json)))

back = SenMLFormat.Json.decode(json)
@assert back == pack
println("read back ", length(back), " records")
# ANCHOR_END: main
