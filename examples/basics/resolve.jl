# Readings from a home water meter: base fields, relative times and resolving.
#
# Rust version: rsenml/examples/basics/src/bin/resolve.rs.

using SenMLFormat

# ANCHOR: main
# The meter sends its total (a sum, in litres) every 10 minutes. The times are
# relative to the base time: -1200 s, -600 s and 0 s.
pack = Pack([
    Record(bn = "urn:dev:mac:0024befffe804ff2:water:", bt = 1_700_000_000, bu = "l",
           bs = 48_000, n = "total", t = -1200, s = 12.5),
    Record(n = "total", t = -600, s = 19.0),
    Record(n = "total", s = 31.5),
])

# Resolving gives every record its full name, unit and time, and adds the base
# sum. "now" is only needed for times below 2^28, which this pack does not use.
for r in resolve(pack)
    println(r.name, " t=", round(Int, r.time), " u=", repr(r.unit), " sum=", r.sum)
end
# ANCHOR_END: main
