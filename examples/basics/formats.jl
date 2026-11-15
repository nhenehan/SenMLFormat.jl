# The thermostat pack in all eight SenML media types, with their sizes.
#
# Rust version: rsenml/examples/basics/src/bin/formats.rs.

using SenMLFormat
using Printf

# ANCHOR: main
pack = Pack([
    Record(bn = "urn:dev:mac:0024befffe804ff1:", bt = 1_700_000_000, bu = "Cel",
           n = "room", v = 21.5),
    Record(n = "setpoint", v = 21.0),
    Record(n = "heating", u = "/", v = 0.4),
])

for media in instances(MediaType)
    bytes = SenMLFormat.encode(media, pack)
    @assert SenMLFormat.decode(media, bytes) == pack
    @printf("%-28s CoAP %3d: %3d bytes\n", content_type(media),
            coap_content_format(media), length(bytes))
end

# EXI is bit-packed by default. Byte-aligned EXI is a little bigger, but every
# value starts on a byte boundary.
aligned = SenMLFormat.Exi.encode(pack; alignment = :byte_aligned)
println("EXI byte-aligned: ", length(aligned), " bytes")

# A content type from an HTTP header or a CoAP option picks the format.
println(media_type("application/senml+cbor"))
# ANCHOR_END: main
