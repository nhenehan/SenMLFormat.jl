"""
    SenML.Exi

The EXI format of SenML
([RFC 8428 section 8](https://www.rfc-editor.org/rfc/rfc8428#section-8)): media
types `application/senml-exi` and `application/sensml-exi`. Strict
schema-informed EXI with the RFC's schema, through JExi.

```julia
bytes = SenML.Exi.encode(pack)                              # bit-packed
bytes = SenML.Exi.encode(pack; alignment = :byte_aligned)   # byte-aligned
SenML.Exi.decode(bytes)
```

- The header carries the EXI options with schemaId "a" (section 8); a stream that
  names another schema (or none) is refused with a `:SchemaId` error. A stream
  without options is read only when the caller gives them (`out_of_band`).
- Strict EXI cannot carry extensions: they are dropped (section 8: "any extensions
  will be lost"), or refused with `extensions = :error`.
- EXI cannot carry -0.0: an EXI Float's mantissa is an EXI Integer, which codes a
  negative number as its magnitude minus one (EXI 7.1.5), so there is no negative
  zero. -0.0 is written as 0.
- No `\$EXI` cookie by default (section 8 says SHOULD NOT over CoAP or HTTP).

The bytes equal rsenml's and EXIficient's for every test case.
"""
module Exi

import JExi as J
using ..SenML: SenML, Record, Pack, Extension, Value, SenMLError, validate,
    syntax_error, incomplete, record_error, RecordBuilder, set!, build, label_from_text,
    label_type, label_text, T_STRING, T_NUMBER, T_VERSION, T_BOOL, T_DATA, L_BN, L_BT,
    L_BU, L_BV, L_BS, L_BVER, L_N, L_U, L_T, L_UT, L_S, L_V, L_VS, L_VB, L_VD,
    decimal_parts, decimal_to_float, base64url_decode, base64url_encode, XML_NAMESPACE,
    EXI_SCHEMA_ID
import ..SenML: finish

include("generated/senml_tables.jl")

const ALIGNMENTS = (:bit_packed, :byte_aligned)

function exi_alignment(a::Symbol)
    a === :bit_packed && return J.ALIGN_BIT_PACKED
    a === :byte_aligned && return J.ALIGN_BYTE_ALIGNED
    throw(ArgumentError("alignment must be :bit_packed or :byte_aligned, not $(repr(a))"))
end

# The options of RFC 8428 section 8: strict, schemaId "a".
exi_options(a::Symbol) = J.strict_options(; alignment = exi_alignment(a), schema_id = EXI_SCHEMA_ID)

# A JExi error as a SenMLError. `bit` is where the operation started; offsets are
# the byte that holds that bit.
function exi_error(e::J.ExiError, bit::Integer)::SenMLError
    e isa J.TruncatedError && return incomplete(:exi)
    if e isa J.SchemaIdError
        return SenMLError(:SchemaId; found = e.stream isa String ? e.stream : nothing)
    end
    (e isa J.HeaderError || e isa J.GrammarError) &&
        return syntax_error(:exi, bit ÷ 8, sprint(showerror, e))
    return SenMLError(:Exi; reason = sprint(showerror, e))
end

structure(reason::String) = SenMLError(:Structure; format = :exi, reason)

#------------------------------------------------------------------------ reading

# Whether the header has options: after an optional `$EXI` cookie come the
# distinguishing bits `10` and the presence bit (https://www.w3.org/TR/exi/#header).
function header_has_options(input::AbstractVector{UInt8})::Bool
    i = firstindex(input)
    if length(input) >= 4 && input[i] == 0x24 && input[i+1] == 0x45 && input[i+2] == 0x58 &&
       input[i+3] == 0x49
        i += 4
    end
    i > lastindex(input) && throw(incomplete(:exi))
    b = input[i]
    b >> 6 == 0b10 ||
        throw(syntax_error(:exi, i - firstindex(input), "not an EXI stream (distinguishing bits)"))
    return b & 0x20 != 0
end

const R_RECORDS = 0
const R_DONE = 1

"""
    RecordReader(bytes; out_of_band = nothing)

Reads the records of a SenML EXI stream one at a time: [`next_record!`](@ref)
until it returns `nothing`, then [`finish`](@ref). `out_of_band` gives the
alignment (`:bit_packed` or `:byte_aligned`) of a stream whose header carries no
options; such a stream is refused (`:SchemaId`) without it.
"""
mutable struct RecordReader{V<:AbstractVector{UInt8}}
    dec::J.Decoder{V}
    state::Int
    index::Int
end

function RecordReader(input::AbstractVector{UInt8}; out_of_band::Union{Nothing,Symbol} = nothing)
    in_header = header_has_options(input)
    options = if in_header
        nothing
    elseif out_of_band !== nothing
        exi_options(out_of_band)
    else
        throw(SenMLError(:SchemaId))
    end
    dec = try
        J.Decoder(input, Tables.GRAMMARS; options)
    catch e
        e isa J.ExiError || rethrow()
        throw(exi_error(e, 0))
    end
    if in_header
        id = dec.options.schema_id
        id isa String && id == EXI_SCHEMA_ID ||
            throw(SenMLError(:SchemaId; found = id isa String ? id : nothing))
    end
    r = RecordReader(dec, R_RECORDS, 0)
    expect(r, J.EV_SD, "missing start of document")
    expect(r, J.EV_SE, "the root element must be sensml")
    is_name(r, "sensml") || throw(structure("the root element must be sensml"))
    return r
end

function next_kind(r::RecordReader)::J.EventKind
    bit = J.bit_position(r.dec)
    try
        return J.next!(r.dec)
    catch e
        e isa J.ExiError || rethrow()
        throw(exi_error(e, bit))
    end
end

function expect(r::RecordReader, k::J.EventKind, reason::String)
    got = next_kind(r)
    got == J.EV_DONE && throw(incomplete(:exi))
    got == k || throw(structure(reason))
    return nothing
end

function is_name(r::RecordReader, local_::String)
    uri, l = J.event_qname(r.dec)
    return uri == XML_NAMESPACE && l == local_
end

"""
    next_record!(reader) -> Union{Record,Nothing}

The next record, or `nothing` at the end of the `sensml` element.
"""
function next_record!(r::RecordReader)::Union{Nothing,Record}
    r.state == R_DONE && return nothing
    k = next_kind(r)
    if k == J.EV_SE && is_name(r, "senml")
    elseif k == J.EV_EE
        r.state = R_DONE
        expect(r, J.EV_ED, "missing end of document")
        return nothing
    elseif k == J.EV_DONE
        throw(incomplete(:exi))
    else
        throw(structure("only senml elements may appear inside sensml"))
    end
    r.index += 1
    index = r.index
    b = RecordBuilder(index)
    while true
        k = next_kind(r)
        if k == J.EV_AT
            # An attribute must be a SenML label in no namespace. The strict
            # grammar only allows schema attributes, but check anyway.
            uri, label = J.event_qname(r.dec)
            l = isempty(uri) ? label_from_text(label) : 0
            l == 0 && throw(structure("an attribute outside the SenML schema"))
            set!(b, l, field(l, J.event_value(r.dec), index))
        elseif k == J.EV_EE
            return build(b)
        elseif k == J.EV_DONE
            throw(incomplete(:exi))
        else
            throw(structure("a senml element has no content"))
        end
    end
end

"""
    finish(reader)

Checks that the stream ends after the document.
"""
function finish(r::RecordReader)
    r.state == R_DONE || throw(incomplete(:exi))
    next_kind(r) == J.EV_DONE || throw(structure("events after the end of the document"))
    return nothing
end

Base.IteratorSize(::Type{<:RecordReader}) = Base.SizeUnknown()
Base.eltype(::Type{<:RecordReader}) = Record
function Base.iterate(r::RecordReader, _ = nothing)
    x = next_record!(r)
    return x === nothing ? nothing : (x, nothing)
end

# The value of a registered label, by the schema's type.
function field(l::Int, value, index::Int)
    t = label_type(l)
    if t == T_STRING && value isa AbstractString
        return String(value)
    elseif t == T_DATA && value isa AbstractString
        d = base64url_decode(value)
        d === nothing && throw(record_error(:InvalidBase64, index))
        return d
    elseif t == T_NUMBER && value isa J.ExiFloat
        # An EXI Float with the special exponent -(2^14) is INF, -INF or NaN
        # (https://www.w3.org/TR/exi/#encodingFloat). These are not SenML numbers.
        value.exponent == J.FLOAT_SPECIAL_EXPONENT &&
            throw(record_error(:NonFinite, index, label_text(l)))
        return decimal_to_float(value.mantissa, value.exponent)
    elseif t == T_VERSION && value isa Int64
        value < 0 && throw(record_error(:InvalidVersion, index))
        return UInt64(value)
    elseif t == T_BOOL && value isa Bool
        return value
    end
    throw(record_error(:WrongType, index, label_text(l)))
end

function read_all(input::AbstractVector{UInt8}, out_of_band::Union{Nothing,Symbol})::Pack
    r = RecordReader(input; out_of_band)
    records = Record[]
    while true
        x = next_record!(r)
        x === nothing && break
        push!(records, x)
    end
    finish(r)
    return Pack(records)
end

"""
    decode(bytes; out_of_band = nothing) -> Pack

Reads a SenML EXI stream and validates the pack. The header must carry options
with schemaId "a", unless `out_of_band` gives the alignment of a stream without
options. Throws a `SenMLError`.
"""
function decode(input::AbstractVector{UInt8}; out_of_band::Union{Nothing,Symbol} = nothing)::Pack
    p = read_all(input, out_of_band)
    validate(p)
    return p
end

"""
    decode_unchecked(bytes; out_of_band = nothing) -> Pack

Reads a SenML EXI stream without the rules of section 4.
"""
decode_unchecked(input::AbstractVector{UInt8}; out_of_band::Union{Nothing,Symbol} = nothing) =
    read_all(input, out_of_band)

#------------------------------------------------------------------------ writing
#
# The writer drives JExi's encoder with the names' ids from the generated tables,
# not with name strings. Attributes go in EXI order (sorted by local name).

const ATTRIBUTE_ORDER = (
    (L_BN, Tables.LN_BN), (L_BS, Tables.LN_BS), (L_BT, Tables.LN_BT), (L_BU, Tables.LN_BU),
    (L_BV, Tables.LN_BV), (L_BVER, Tables.LN_BVER), (L_N, Tables.LN_N), (L_S, Tables.LN_S),
    (L_T, Tables.LN_T), (L_U, Tables.LN_U), (L_UT, Tables.LN_UT), (L_V, Tables.LN_V),
    (L_VB, Tables.LN_VB), (L_VD, Tables.LN_VD), (L_VS, Tables.LN_VS),
)

"""
    StreamEncoder(; alignment = :bit_packed, cookie = false, extensions = :drop)

Writes a SenSML EXI stream record by record: [`record!`](@ref) each record, then
[`finish!`](@ref) for the bytes. It does not validate. `alignment` is
`:bit_packed` (the smallest) or `:byte_aligned`; `cookie` writes the `\$EXI`
cookie; `extensions` is `:drop` or `:error`.
"""
mutable struct StreamEncoder
    enc::J.Encoder
    extensions::Symbol
    index::Int
end

function StreamEncoder(; alignment::Symbol = :bit_packed, cookie::Bool = false, extensions::Symbol = :drop)
    extensions in (:drop, :error) ||
        throw(ArgumentError("extensions must be :drop or :error, not $(repr(extensions))"))
    header = J.HeaderConfig(; cookie, include_options = true)
    enc = J.Encoder(Tables.GRAMMARS, exi_options(alignment); header)
    s = StreamEncoder(enc, extensions, 0)
    checked(s) do e
        J.start_document!(e)
        J.start_element!(e, Tables.LN_SENSML)
    end
    return s
end

function checked(f, s::StreamEncoder)
    bit = J.bit_position(s.enc)
    try
        f(s.enc)
    catch e
        e isa J.ExiError || rethrow()
        throw(exi_error(e, bit))
    end
    return nothing
end

function number_of(r::Record, l::Int)::Union{Nothing,Float64}
    l == L_BT && return r.bt
    l == L_BV && return r.bv
    l == L_BS && return r.bs
    l == L_S && return r.s
    l == L_T && return r.t
    l == L_UT && return r.ut
    l == L_V && return r.value isa Float64 ? r.value : nothing
    return nothing
end

# One attribute, when the record has it. (Each attribute is written from its own
# field, not from a loop over a tuple of mixed types, which would box every value.)
put!(::J.Encoder, _, ::Nothing) = nothing
put!(e::J.Encoder, q, x::String) = J.attribute!(e, q, x)

# Doubles go to JExi as EXI Floats (a decimal mantissa and exponent): the shortest
# decimal digits, with trailing zeros moved into the exponent. That is how
# EXIficient puts the same XML attribute text into standard form, so the bytes
# are the same as for the text form.
# https://www.w3.org/TR/exi/#encodingFloat
put_number!(::J.Encoder, _, ::Nothing) = nothing
function put_number!(e::J.Encoder, q, v::Float64)
    m, x = decimal_parts(v)
    J.attribute!(e, q, J.ExiFloat(m, Int16(x)))
    return nothing
end

"""
    record!(enc, record)

Writes the next record of the stream.
"""
function record!(s::StreamEncoder, r::Record)
    s.index += 1
    index = s.index
    if !isempty(r.extensions) && s.extensions === :error
        throw(SenMLError(:Unrepresentable; format = :exi, reason = "strict EXI cannot carry extension labels"))
    end
    # Numbers are checked before anything is written, so a bad record leaves no
    # half-written element.
    for (l, _) in ATTRIBUTE_ORDER
        v = number_of(r, l)
        v === nothing || isfinite(v) || throw(record_error(:NonFinite, index, label_text(l)))
    end
    # `bver` is an xs:int (https://www.w3.org/TR/xmlschema-2/#int).
    if r.bver !== nothing && r.bver > 2_147_483_647
        throw(SenMLError(:Unrepresentable; format = :exi, reason = "bver above the xs:int range"))
    end
    data = r.value isa Vector{UInt8} ? base64url_encode(r.value) : nothing
    checked(s) do e
        # Attributes in the schema's order (alphabetical, ATTRIBUTE_ORDER).
        J.start_element!(e, Tables.LN_SENML)
        put!(e, Tables.LN_BN, r.bn)
        put_number!(e, Tables.LN_BS, r.bs)
        put_number!(e, Tables.LN_BT, r.bt)
        put!(e, Tables.LN_BU, r.bu)
        put_number!(e, Tables.LN_BV, r.bv)
        bver = r.bver
        bver === nothing || J.attribute!(e, Tables.LN_BVER, Int64(bver))
        put!(e, Tables.LN_N, r.n)
        put_number!(e, Tables.LN_S, r.s)
        put_number!(e, Tables.LN_T, r.t)
        put!(e, Tables.LN_U, r.u)
        put_number!(e, Tables.LN_UT, r.ut)
        v = r.value
        v isa Float64 && put_number!(e, Tables.LN_V, v)
        v isa Bool && J.attribute!(e, Tables.LN_VB, v)
        data === nothing || J.attribute!(e, Tables.LN_VD, data)
        v isa String && J.attribute!(e, Tables.LN_VS, v)
        J.end_element!(e)
    end
    return nothing
end

"""
    finish!(enc) -> Vector{UInt8}

Ends the stream and returns its bytes.
"""
function finish!(s::StreamEncoder)::Vector{UInt8}
    checked(s) do e
        J.end_element!(e)
        J.end_document!(e)
    end
    bit = J.bit_position(s.enc)
    try
        return copy(J.finish!(s.enc))
    catch e
        e isa J.ExiError || rethrow()
        throw(exi_error(e, bit))
    end
end

"""
    encode_unchecked(pack; alignment = :bit_packed, cookie = false, extensions = :drop) -> Vector{UInt8}

Writes a pack as it is, without validating (values EXI cannot carry are still
refused).
"""
function encode_unchecked(p::AbstractVector{Record}; alignment::Symbol = :bit_packed, cookie::Bool = false,
    extensions::Symbol = :drop)::Vector{UInt8}
    s = StreamEncoder(; alignment, cookie, extensions)
    for r in p
        record!(s, r)
    end
    return finish!(s)
end

"""
    encode(pack; alignment = :bit_packed, cookie = false, extensions = :drop) -> Vector{UInt8}

Validates a pack and writes it as SenML EXI: strict, with the options and schemaId
"a" in the header. `alignment` is `:bit_packed` (the default) or `:byte_aligned`;
`cookie` writes the `\$EXI` cookie; `extensions = :error` refuses a pack with
extensions instead of dropping them.
"""
function encode(p::AbstractVector{Record}; alignment::Symbol = :bit_packed, cookie::Bool = false,
    extensions::Symbol = :drop)::Vector{UInt8}
    validate(p)
    return encode_unchecked(p; alignment, cookie, extensions)
end

end # module Exi
