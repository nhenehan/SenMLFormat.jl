# decode/encode by media type: the twin of rsenml's facade crate.
# https://www.rfc-editor.org/rfc/rfc8428#section-12.3

bytes_of(input::AbstractVector{UInt8}) = input
bytes_of(input::AbstractString) = codeunits(String(input))

"""
    decode(media::MediaType, input) -> Pack

Reads and checks a pack of the given media type. `input` is bytes or a string.
The SenSML types also accept streams; for CBOR that means an indefinite-length
array. For EXI, the header must carry its options (RFC 8428 section 8); use
`SenMLFormat.Exi.decode` with `out_of_band` for streams without them.

```julia
pack = SenMLFormat.decode(SENML_CBOR, bytes)
```
"""
function decode(media::MediaType, input)::Pack
    b = bytes_of(input)
    f = media_format(media)
    f === :json && return Json.decode(b)
    f === :cbor && return is_streaming(media) ? Cbor.decode_sensml(b) : Cbor.decode(b)
    f === :xml && return Xml.decode(b)
    return Exi.decode(b)
end

"""
    encode(media::MediaType, pack) -> Vector{UInt8}

Checks a pack and writes it in the given media type. SenSML CBOR uses an
indefinite-length array; the other SenSML types are written the same as SenML.
EXI is bit-packed with no cookie; `SenMLFormat.Exi.encode` has the other choices.
"""
function encode(media::MediaType, p::AbstractVector{Record})::Vector{UInt8}
    f = media_format(media)
    f === :json && return Json.encode(p)
    f === :cbor && return is_streaming(media) ? Cbor.encode_sensml(p) : Cbor.encode(p)
    f === :xml && return Xml.encode(p)
    return Exi.encode(p)
end

"""
    encode_unchecked(media::MediaType, pack) -> Vector{UInt8}

[`encode`](@ref) without checking the pack first, for packs that are already valid
(decoded, or built by trusted code). Values a format cannot write are still
refused.
"""
function encode_unchecked(media::MediaType, p::AbstractVector{Record})::Vector{UInt8}
    f = media_format(media)
    f === :json && return Json.encode_unchecked(p)
    if f === :cbor
        is_streaming(media) || return Cbor.encode_unchecked(p)
        io = IOBuffer()
        s = Cbor.StreamEncoder()
        for r in p
            Cbor.record!(s, io, r)
        end
        Cbor.finish!(s, io)
        return take!(io)
    end
    f === :xml && return Xml.encode_unchecked(p)
    return Exi.encode_unchecked(p)
end
