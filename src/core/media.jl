# Media types and CoAP Content-Formats.
# https://www.rfc-editor.org/rfc/rfc8428#section-12.3
# https://www.rfc-editor.org/rfc/rfc8428#section-12.5

"""
    MediaType

The eight SenML and SenSML media types: `SENML_JSON`, `SENSML_JSON`, `SENML_CBOR`,
`SENSML_CBOR`, `SENML_XML`, `SENSML_XML`, `SENML_EXI`, `SENSML_EXI`. For each
format, SenML comes before SenSML.
"""
@enum MediaType SENML_JSON SENSML_JSON SENML_CBOR SENSML_CBOR SENML_XML SENSML_XML SENML_EXI SENSML_EXI

const CONTENT_TYPES = (
    "application/senml+json", "application/sensml+json",
    "application/senml+cbor", "application/sensml+cbor",
    "application/senml+xml", "application/sensml+xml",
    "application/senml-exi", "application/sensml-exi",
)

# Table 8 of section 12.5.
const COAP_CONTENT_FORMATS = (110, 111, 112, 113, 310, 311, 114, 115)

"The media type name, for example `application/senml+json`."
content_type(m::MediaType) = CONTENT_TYPES[Int(m)+1]

"The CoAP Content-Format ID (Table 8 in RFC 8428 section 12.5)."
coap_content_format(m::MediaType) = COAP_CONTENT_FORMATS[Int(m)+1]

"The format of a media type: `:json`, `:cbor`, `:xml` or `:exi`."
media_format(m::MediaType) = (:json, :cbor, :xml, :exi)[Int(m)÷2+1]

"SenSML (streaming, RFC 8428 section 4.8) rather than SenML."
is_streaming(m::MediaType) = isodd(Int(m))

"""
    media_type(format::Symbol, streaming::Bool) -> MediaType
    media_type(content_type::AbstractString) -> Union{MediaType,Nothing}
    media_type(coap_content_format::Integer) -> Union{MediaType,Nothing}

The media type of a format (`:json`, `:cbor`, `:xml`, `:exi`), of a content type
(case and parameters such as `; charset=...` are ignored), or of a CoAP
Content-Format ID.
"""
function media_type(format::Symbol, streaming::Bool)
    i = format === :json ? 0 : format === :cbor ? 2 : format === :xml ? 4 :
        format === :exi ? 6 : throw(ArgumentError("unknown SenML format $(repr(format))"))
    return MediaType(i + streaming)
end

ascii_lower(c::UInt8) = UInt8('A') <= c <= UInt8('Z') ? c + 0x20 : c

function media_type(text::AbstractString)::Union{Nothing,MediaType}
    essence = codeunits(strip(first(split(text, ';'))))
    for m in instances(MediaType)
        name = codeunits(content_type(m))
        length(essence) == length(name) && all(i -> ascii_lower(essence[i]) == name[i], eachindex(name)) &&
            return m
    end
    return nothing
end

function media_type(id::Integer)::Union{Nothing,MediaType}
    for m in instances(MediaType)
        coap_content_format(m) == id && return m
    end
    return nothing
end
