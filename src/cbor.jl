"""
    SenML.Cbor

The CBOR format of SenML
([RFC 8428 section 6](https://www.rfc-editor.org/rfc/rfc8428#section-6)): media
types `application/senml+cbor` and, for streams, `application/sensml+cbor`. CBOR
itself is [RFC 8949](https://www.rfc-editor.org/rfc/rfc8949).

```julia
pack = Pack([Record(n = "urn:dev:ow:10e2073a01080063", u = "Cel", v = 23.1)])
bytes = SenML.Cbor.encode(pack)
SenML.Cbor.decode(bytes) == pack
```

Reading:
- Registered labels are the integer keys of Table 4. A text key that spells a
  registered label (`"v"`) is not that label in CBOR, so it is an unknown field
  and is ignored ([section 4.4](https://www.rfc-editor.org/rfc/rfc8428#section-4.4));
  its value is skipped, not kept, so a translation to JSON cannot write the label
  twice. Unknown integer keys are ignored. Unknown text keys are extensions (kept
  when their value is a scalar), and fail when they end in `_`.
- Numbers may be integers, half/single/double floats, or decimal fractions
  (tag 4). `bver` may only be an unsigned integer. Text and byte strings must have
  a definite length.
- A SenML pack is a definite-length array. A SenSML stream may also be an
  indefinite-length one ([`decode_sensml`](@ref)).

Writing puts every number in the smallest form that reads back as the same double
(an integer when it is a whole number, else a half, single or double float), the
integer keys in the order of the RFC's examples, then extensions under text keys.
This writes the RFC's section 6 example byte for byte.
"""
module Cbor

using ..SenML: SenML, Record, Pack, Extension, Value, SenMLError, Validator, check!,
    validate, syntax_error, incomplete, record_error, RecordBuilder, set!, extension!,
    skipped_extension, build, label_from_text, label_from_cbor, label_type, label_text,
    value_label, LABEL_CBOR, T_STRING, T_NUMBER, T_VERSION, T_BOOL, T_DATA,
    decimal_to_float, as_exact_int, to_float16_exact, to_float32_exact, L_BN, L_BT, L_BU,
    L_BV, L_BS, L_N, L_U, L_T, L_UT, L_S
import ..SenML: finish

#------------------------------------------------------------- reading CBOR items
#
# Item types, from the initial byte (the way minicbor, the library rsenml uses,
# classifies them, so the same input gives the same error kind).
# https://www.rfc-editor.org/rfc/rfc8949#section-3

const TY_UINT = 1
const TY_NINT = 2
const TY_BYTES = 3
const TY_BYTES_INDEF = 4
const TY_STR = 5
const TY_STR_INDEF = 6
const TY_ARRAY = 7
const TY_ARRAY_INDEF = 8
const TY_MAP = 9
const TY_MAP_INDEF = 10
const TY_TAG = 11
const TY_BOOL = 12
const TY_NULL = 13
const TY_UNDEFINED = 14
const TY_SIMPLE = 15
const TY_F16 = 16
const TY_F32 = 17
const TY_F64 = 18
const TY_BREAK = 19
const TY_UNKNOWN = 20

# A CBOR decoder over bytes `b`; `pos` is the next byte (1-based).
mutable struct Decoder{B<:AbstractVector{UInt8}}
    b::B
    pos::Int
end

serr(at::Int, reason::String) = syntax_error(:cbor, at - 1, reason)
malformed(at::Int) = serr(at, "malformed CBOR")
mismatch(at::Int) = serr(at, "unexpected CBOR data item")

remaining(d::Decoder) = length(d.b) - d.pos + 1

function datatype(d::Decoder)::Int
    d.pos > length(d.b) && throw(incomplete(:cbor))
    ib = d.b[d.pos]
    major = ib >> 5
    info = ib & 0x1f
    if major == 0
        return info < 28 ? TY_UINT : TY_UNKNOWN
    elseif major == 1
        return info < 28 ? TY_NINT : TY_UNKNOWN
    elseif major == 2
        return info == 31 ? TY_BYTES_INDEF : info < 28 ? TY_BYTES : TY_UNKNOWN
    elseif major == 3
        return info == 31 ? TY_STR_INDEF : info < 28 ? TY_STR : TY_UNKNOWN
    elseif major == 4
        return info == 31 ? TY_ARRAY_INDEF : info < 28 ? TY_ARRAY : TY_UNKNOWN
    elseif major == 5
        return info == 31 ? TY_MAP_INDEF : info < 28 ? TY_MAP : TY_UNKNOWN
    elseif major == 6
        return info < 28 ? TY_TAG : TY_UNKNOWN
    else
        info == 20 || info == 21 ? (return TY_BOOL) :
        info == 22 ? (return TY_NULL) :
        info == 23 ? (return TY_UNDEFINED) :
        info < 20 || info == 24 ? (return TY_SIMPLE) :
        info == 25 ? (return TY_F16) :
        info == 26 ? (return TY_F32) :
        info == 27 ? (return TY_F64) :
        info == 31 ? (return TY_BREAK) : (return TY_UNKNOWN)
    end
end

const INDEF = typemax(UInt64)

# The initial byte and its argument: (major type, additional info, argument).
# The argument of an indefinite length (info 31) is INDEF. Reserved additional
# info (28-30) is malformed.
function head!(d::Decoder)::Tuple{UInt8,UInt8,UInt64}
    at = d.pos
    at > length(d.b) && throw(incomplete(:cbor))
    ib = d.b[at]
    major = ib >> 5
    info = ib & 0x1f
    if info < 24
        d.pos += 1
        return (major, info, UInt64(info))
    elseif info <= 27
        n = 1 << (info - 24)  # 1, 2, 4 or 8 bytes
        at + n > length(d.b) && throw(incomplete(:cbor))
        x = UInt64(0)
        for i in 1:n
            x = (x << 8) | d.b[at+i]
        end
        d.pos = at + 1 + n
        return (major, info, x)
    elseif info == 31 && major in (2, 3, 4, 5, 7)
        d.pos += 1
        return (major, info, INDEF)
    end
    throw(malformed(at))
end

# An integer of either sign (CBOR integers run from -2^64 to 2^64 - 1).
function read_int!(d::Decoder)::Int128
    at = d.pos
    ty = datatype(d)
    (ty == TY_UINT || ty == TY_NINT) || throw(mismatch(at))
    major, _, x = head!(d)
    return major == 0 ? Int128(x) : -1 - Int128(x)
end

function read_uint!(d::Decoder)::UInt64
    at = d.pos
    datatype(d) == TY_UINT || throw(mismatch(at))
    return head!(d)[3]
end

# The content of a definite-length text or byte string.
function read_content!(d::Decoder, ty::Int)::Vector{UInt8}
    at = d.pos
    datatype(d) == ty || throw(mismatch(at))
    _, _, n = head!(d)
    n > remaining(d) && throw(incomplete(:cbor))
    out = Vector{UInt8}(undef, n)
    copyto!(out, 1, d.b, d.pos, Int(n))
    d.pos += Int(n)
    return out
end

function read_str!(d::Decoder)::String
    at = d.pos
    s = String(read_content!(d, TY_STR))
    isvalid(s) || throw(malformed(at))
    return s
end

read_bytes!(d::Decoder) = read_content!(d, TY_BYTES)

function read_bool!(d::Decoder)::Bool
    at = d.pos
    datatype(d) == TY_BOOL || throw(mismatch(at))
    return head!(d)[2] == 21
end

# Skips one complete item: tags, nested arrays and maps, indefinite strings. It
# keeps a stack of item counts instead of calling itself, so deep nesting cannot
# overflow the call stack.
function skip!(d::Decoder)
    left = UInt64[1]  # items still to read in each open container
    indef = Bool[false]
    while !isempty(left)
        if !indef[end] && left[end] == 0
            pop!(left)
            pop!(indef)
            continue
        end
        at = d.pos
        ty = datatype(d)
        if ty == TY_BREAK
            indef[end] || throw(mismatch(at))
            d.pos += 1
            pop!(left)
            pop!(indef)
            continue
        end
        # A tag belongs to the item after it.
        while ty == TY_TAG
            head!(d)
            ty = datatype(d)
        end
        indef[end] || (left[end] -= 1)
        _, _, n = head!(d)
        if ty == TY_UNKNOWN || ty == TY_BREAK
            throw(malformed(at))
        elseif ty == TY_BYTES || ty == TY_STR
            n > remaining(d) && throw(incomplete(:cbor))
            d.pos += Int(n)
        elseif ty == TY_BYTES_INDEF || ty == TY_STR_INDEF
            # Chunks of the same major type, each of definite length, then a break.
            while true
                cat = d.pos
                cty = datatype(d)
                if cty == TY_BREAK
                    d.pos += 1
                    break
                end
                cty == (ty == TY_STR_INDEF ? TY_STR : TY_BYTES) || throw(malformed(cat))
                _, _, cn = head!(d)
                cn > remaining(d) && throw(incomplete(:cbor))
                d.pos += Int(cn)
            end
        elseif ty == TY_ARRAY || ty == TY_MAP
            push!(left, ty == TY_MAP ? (n > INDEF ÷ 2 ? INDEF : 2n) : n)
            push!(indef, false)
        elseif ty == TY_ARRAY_INDEF || ty == TY_MAP_INDEF
            push!(left, 0)
            push!(indef, true)
        end
    end
    return nothing
end

#----------------------------------------------------------------- SenML records

# CBOR tag 4, decimal fraction [exponent, mantissa]: mantissa * 10^exponent.
# https://www.rfc-editor.org/rfc/rfc8949#section-3.4.4
const DECIMAL_FRACTION = 4

function decimal_fraction!(d::Decoder)::Float64
    at = d.pos
    ty = datatype(d)
    (ty == TY_ARRAY || ty == TY_ARRAY_INDEF) || throw(mismatch(at))
    _, _, n = head!(d)
    n == 2 || throw(serr(at, "a decimal fraction is a 2-element array"))
    e = read_int!(d)
    typemin(Int64) <= e <= typemax(Int64) || throw(serr(at, "decimal fraction exponent out of range"))
    m = read_int!(d)
    return decimal_to_float(m, e)
end

# A number of any CBOR form SenML allows, or `nothing` (nothing read) when the item
# is not a number: integers, floats and decimal fractions (section 6).
function numeric!(d::Decoder, ty::Int)::Union{Nothing,Float64,UInt64}
    if ty == TY_UINT
        return read_uint!(d)
    elseif ty == TY_NINT
        return Float64(read_int!(d))
    elseif ty == TY_F16
        _, _, x = head!(d)
        return Float64(reinterpret(Float16, x % UInt16))
    elseif ty == TY_F32
        _, _, x = head!(d)
        return Float64(reinterpret(Float32, x % UInt32))
    elseif ty == TY_F64
        _, _, x = head!(d)
        return reinterpret(Float64, x)
    elseif ty == TY_TAG
        # Look at the tag without reading it: any tag but 4 is not a number.
        save = d.pos
        _, _, tag = head!(d)
        if tag != DECIMAL_FRACTION
            d.pos = save
            return nothing
        end
        return decimal_fraction!(d)
    end
    return nothing
end

# The value of a registered label, which must have the type the label needs.
function field!(d::Decoder, l::Int, index::Int)
    at = d.pos
    ty = datatype(d)
    t = label_type(l)
    if t == T_STRING
        ty == TY_STR && return read_str!(d)
        ty == TY_STR_INDEF && throw(serr(at, "text must have a definite length"))
    elseif t == T_NUMBER
        x = numeric!(d, ty)
        x === nothing || return x
    elseif t == T_VERSION
        ty == TY_UINT && return read_uint!(d)
    elseif t == T_BOOL
        ty == TY_BOOL && return read_bool!(d)
    else # T_DATA
        ty == TY_BYTES && return read_bytes!(d)
        ty == TY_BYTES_INDEF && throw(serr(at, "Data Value must have a definite length"))
    end
    throw(record_error(:WrongType, index, label_text(l)))
end

# The value of an unknown text key. Scalars are kept; arrays, maps, other tags and
# the like are skipped (after the `_` check).
function extension_field!(d::Decoder, b::RecordBuilder, label::String)
    ty = datatype(d)
    if ty == TY_STR
        extension!(b, label, read_str!(d))
    elseif ty == TY_BYTES
        extension!(b, label, read_bytes!(d))
    elseif ty == TY_BOOL
        extension!(b, label, read_bool!(d))
    else
        x = numeric!(d, ty)
        if x === nothing
            skipped_extension(b, label)
            skip!(d)
        else
            extension!(b, label, x)
        end
    end
    return nothing
end

function entry!(d::Decoder, b::RecordBuilder, index::Int)
    at = d.pos
    ty = datatype(d)
    if ty == TY_UINT || ty == TY_NINT
        key = read_int!(d)
        l = -6 <= key <= 8 ? label_from_cbor(Int(key)) : 0
        if l != 0
            set!(b, l, field!(d, l, index))
        else
            # Table 4 is complete (section 6 says no more integer keys will be
            # added), so other integer keys carry nothing we know.
            skip!(d)
        end
    elseif ty == TY_STR
        key = read_str!(d)
        if label_from_text(key) != 0
            # RFC 8428 4.4: "MUST ignore fields they don't recognize". In CBOR, a
            # registered label is its Table 4 integer (section 6), and labels
            # added later are text keys (12.2; RFC 9193 section 8).
            # https://www.rfc-editor.org/rfc/rfc8428#section-4.4
            # https://www.rfc-editor.org/rfc/rfc8428#section-12.2
            # https://www.rfc-editor.org/rfc/rfc9193#section-8
            skip!(d)
        else
            extension_field!(d, b, key)
        end
    elseif ty == TY_STR_INDEF
        throw(serr(at, "map keys must be definite-length strings"))
    else
        throw(serr(at, "map keys must be integers or text strings"))
    end
    return nothing
end

# One record: a CBOR map, of definite length (`left` counts down) or indefinite
# length (ends at a break byte).
function read_record!(d::Decoder, index::Int)::Record
    at = d.pos
    ty = datatype(d)
    (ty == TY_MAP || ty == TY_MAP_INDEF) || throw(serr(at, "a SenML record is a CBOR map"))
    _, _, n = head!(d)
    indefinite = ty == TY_MAP_INDEF
    b = RecordBuilder(index)
    left = n
    while true
        if indefinite
            if datatype(d) == TY_BREAK
                d.pos += 1
                break
            end
        else
            left == 0 && break
            left -= 1
        end
        entry!(d, b, index)
    end
    return build(b)
end

#--------------------------------------------------------------- the outer array

const ST_START = 0
const ST_ITEMS = 1
const ST_DONE = 2

mutable struct Cursor
    pos::Int
    state::Int
    left::UInt64  # records left in a definite-length array
    indefinite::Bool  # an indefinite-length array, which ends at a break byte
    index::Int
    streaming::Bool  # accept an indefinite-length array (SenSML)
end

Cursor(streaming::Bool) = Cursor(1, ST_START, 0, false, 0, streaming)

const END = :end

# One record (or the end of the array). Errors leave the cursor where it was, so
# a caller that gets an Incomplete error can add bytes and try again.
function step!(c::Cursor, b::AbstractVector{UInt8})::Union{Record,Symbol}
    d = Decoder(b, c.pos)
    while true
        if c.state == ST_DONE
            return END
        elseif c.state == ST_START
            at = d.pos
            ty = datatype(d)
            if ty == TY_ARRAY || (ty == TY_ARRAY_INDEF && c.streaming)
                _, _, n = head!(d)
                c.indefinite = ty == TY_ARRAY_INDEF
                c.left = c.indefinite ? 0 : n
            elseif ty == TY_ARRAY_INDEF
                throw(serr(at, "a SenML pack must be a definite-length array (SenSML may be indefinite)"))
            else
                throw(serr(at, "a SenML pack is a CBOR array"))
            end
            c.pos = d.pos
            c.state = ST_ITEMS
        elseif !c.indefinite && c.left == 0
            c.state = ST_DONE
            return END
        else
            at = d.pos
            if c.indefinite && datatype(d) == TY_BREAK
                c.pos = at + 1
                c.state = ST_DONE
                return END
            end
            r = read_record!(d, c.index + 1)
            c.pos = d.pos
            c.index += 1
            c.indefinite || (c.left -= 1)
            return r
        end
    end
end

function finish_cursor(c::Cursor, b::AbstractVector{UInt8})
    c.state == ST_DONE || throw(incomplete(:cbor))
    c.pos == length(b) + 1 || throw(serr(c.pos, "data after the end of the pack"))
    return nothing
end

#------------------------------------------------------------------- public API

"""
    RecordReader(input; sensml = false)

Reads the records of a complete SenML CBOR pack one at a time. With `sensml`, the
array may also have an indefinite length (a SenSML stream). Iterate it, or call
[`next_record!`](@ref) until it returns `nothing`, then [`finish`](@ref).
"""
struct RecordReader{B<:AbstractVector{UInt8}}
    input::B
    cursor::Cursor
end

RecordReader(input::AbstractVector{UInt8}; sensml::Bool = false) =
    RecordReader{typeof(input)}(input, Cursor(sensml))

"""
    next_record!(reader) -> Union{Record,Nothing}

The next record, or `nothing` at the end of the array (for a stream decoder: also
when more bytes are needed).
"""
function next_record!(r::RecordReader)::Union{Nothing,Record}
    x = step!(r.cursor, r.input)
    return x isa Record ? x : nothing
end

"Byte offset (0-based) after the last record read."
position(r::RecordReader) = r.cursor.pos - 1

"Checks that the array ended and nothing follows it."
finish(r::RecordReader) = finish_cursor(r.cursor, r.input)

Base.IteratorSize(::Type{<:RecordReader}) = Base.SizeUnknown()
Base.eltype(::Type{<:RecordReader}) = Record
function Base.iterate(r::RecordReader, _ = nothing)
    x = next_record!(r)
    return x === nothing ? nothing : (x, nothing)
end

function read_all(input::AbstractVector{UInt8}, sensml::Bool)::Pack
    r = RecordReader(input; sensml)
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
    decode_unchecked(bytes) -> Pack

Reads a complete SenML CBOR pack (a definite-length array), checking only the CBOR
form. Use `validate` for the rules of section 4.
"""
decode_unchecked(input::AbstractVector{UInt8}) = read_all(input, false)

"""
    decode(bytes) -> Pack

Reads a complete SenML CBOR pack (a definite-length array) and validates it.
Throws a `SenMLError`.
"""
function decode(input::AbstractVector{UInt8})::Pack
    p = read_all(input, false)
    validate(p)
    return p
end

"""
    decode_sensml(bytes) -> Pack

Reads a complete SenSML CBOR stream, whose array may have an indefinite length
(section 6), and validates it.
"""
function decode_sensml(input::AbstractVector{UInt8})::Pack
    p = read_all(input, true)
    validate(p)
    return p
end

"""
    StreamDecoder(; registered_units = false)

Decodes a SenSML CBOR stream
([section 4.8](https://www.rfc-editor.org/rfc/rfc8428#section-4.8)) as its bytes
arrive. `push!` bytes, then call [`next_record!`](@ref) until it returns
`nothing`; each record is ready (and validated) once all of its bytes are in.
"""
mutable struct StreamDecoder
    buf::Vector{UInt8}
    cursor::Cursor
    validator::Validator
end

StreamDecoder(; registered_units::Bool = false) =
    StreamDecoder(UInt8[], Cursor(true), Validator(; registered_units))

function Base.push!(d::StreamDecoder, bytes::AbstractVector{UInt8})
    # Drop the bytes already read once they fill more than half of the buffer
    # (and more than 4096 bytes).
    read = d.cursor.pos - 1
    if read > 4096 && read * 2 > length(d.buf)
        deleteat!(d.buf, 1:read)
        d.cursor.pos = 1
    end
    append!(d.buf, bytes)
    return d
end

function next_record!(d::StreamDecoder)::Union{Nothing,Record}
    x = try
        step!(d.cursor, d.buf)
    catch e
        (e isa SenMLError && e.kind === :Incomplete) || rethrow()
        return nothing
    end
    x isa Record || return nothing
    check!(d.validator, x)
    return x
end

"The end of the array (or its break code) has been read."
isfinished(d::StreamDecoder) = d.cursor.state == ST_DONE

"""
    finish(d::StreamDecoder)

Ends the stream. It must be closed, hold at least one record, and have nothing
after it.
"""
function finish(d::StreamDecoder)
    finish_cursor(d.cursor, d.buf)
    return finish(d.validator)
end

#----------------------------------------------------------------------- writing

# The initial byte and argument in the smallest form.
function write_head(io::IO, major::Integer, n::UInt64)
    m = UInt8(major) << 5
    if n < 24
        write(io, m | (n % UInt8))
    elseif n <= 0xff
        write(io, m | 0x18, n % UInt8)
    elseif n <= 0xffff
        write(io, m | 0x19, hton(n % UInt16))
    elseif n <= 0xffff_ffff
        write(io, m | 0x1a, hton(n % UInt32))
    else
        write(io, m | 0x1b, hton(n))
    end
    return nothing
end

write_int(io::IO, i::Int64) =
    i >= 0 ? write_head(io, 0, i % UInt64) : write_head(io, 1, ~(i % UInt64))

function write_text(io::IO, s::AbstractString)
    write_head(io, 3, UInt64(ncodeunits(s)))
    write(io, s)
    return nothing
end

# The smallest exact form, tried in order: integer, half, single, double float.
# `-0.0` is not an integer (it would lose its sign), so it becomes a half float.
function write_number(io::IO, v::Float64, label::AbstractString, index::Int)
    isfinite(v) || throw(record_error(:NonFinite, index, label))
    i = as_exact_int(v)
    if i !== nothing
        write_int(io, i)
        return nothing
    end
    h = to_float16_exact(v)
    if h !== nothing
        write(io, 0xf9, hton(reinterpret(UInt16, h)))
        return nothing
    end
    f = to_float32_exact(v)
    if f !== nothing
        write(io, 0xfa, hton(reinterpret(UInt32, f)))
    else
        write(io, 0xfb, hton(reinterpret(UInt64, v)))
    end
    return nothing
end

# A string or number field, when present: its integer key, then its value.
write_field(::IO, ::Int, ::Nothing, ::Int) = nothing
function write_field(io::IO, l::Int, x::String, ::Int)
    write_int(io, Int64(LABEL_CBOR[l]))
    write_text(io, x)
    return nothing
end
function write_field(io::IO, l::Int, x::Float64, index::Int)
    write_int(io, Int64(LABEL_CBOR[l]))
    write_number(io, x, label_text(l), index)
    return nothing
end

function write_value(io::IO, v::Value, label::AbstractString, index::Int)
    if v isa Float64
        write_number(io, v, label, index)
    elseif v isa String
        write_text(io, v)
    elseif v isa Bool
        write(io, v ? 0xf5 : 0xf4)
    else
        write_head(io, 2, UInt64(length(v)))
        write(io, v)
    end
    return nothing
end

field_count(r::Record) =
    (r.bn !== nothing) + (r.bt !== nothing) + (r.bu !== nothing) + (r.bv !== nothing) +
    (r.bs !== nothing) + (r.bver !== nothing) + (r.n !== nothing) + (r.u !== nothing) +
    (r.value !== nothing) + (r.s !== nothing) + (r.t !== nothing) + (r.ut !== nothing) +
    length(r.extensions)

"""
    encode_record(io, record, index)

Writes one record map (a definite-length map). `index` (1-based) is only used in
error reports.
"""
function encode_record(io::IO, r::Record, index::Integer = 1)
    index = Int(index)
    write_head(io, 5, UInt64(field_count(r)))
    # One call per field, not a loop over a tuple: the fields have different
    # types, and a loop over them would box each one.
    write_field(io, L_BN, r.bn, index)
    write_field(io, L_BT, r.bt, index)
    write_field(io, L_BU, r.bu, index)
    write_field(io, L_BV, r.bv, index)
    write_field(io, L_BS, r.bs, index)
    if r.bver !== nothing
        write_int(io, Int64(-1))
        write_head(io, 0, r.bver)
    end
    write_field(io, L_N, r.n, index)
    write_field(io, L_U, r.u, index)
    write_field(io, L_T, r.t, index)
    write_field(io, L_UT, r.ut, index)
    write_field(io, L_S, r.s, index)
    v = r.value
    if v !== nothing
        l = value_label(v)
        write_int(io, Int64(LABEL_CBOR[l]))
        write_value(io, v, label_text(l), index)
    end
    for e in r.extensions
        write_text(io, e.label)
        write_value(io, e.value, e.label, index)
    end
    return nothing
end

"""
    encode_unchecked(pack) -> Vector{UInt8}

Writes a pack (a definite-length array) as it is, without validating (infinite and
NaN numbers are still refused).
"""
function encode_unchecked(p::AbstractVector{Record})::Vector{UInt8}
    io = IOBuffer()
    write_head(io, 4, UInt64(length(p)))
    for (i, r) in enumerate(p)
        encode_record(io, r, i)
    end
    return take!(io)
end

"""
    encode(pack) -> Vector{UInt8}

Validates a pack and writes it as SenML CBOR (a definite-length array).
"""
function encode(p::AbstractVector{Record})::Vector{UInt8}
    validate(p)
    return encode_unchecked(p)
end

"""
    encode_sensml(pack) -> Vector{UInt8}

Validates a pack and writes it as a SenSML stream: an indefinite-length array.
"""
function encode_sensml(p::AbstractVector{Record})::Vector{UInt8}
    validate(p)
    io = IOBuffer()
    s = StreamEncoder()
    for r in p
        record!(s, io, r)
    end
    finish!(s, io)
    return take!(io)
end

"""
    StreamEncoder()

Writes a SenSML CBOR stream one piece at a time: the start of an indefinite-length
array (`0x9f`) before the first record ([`record!`](@ref)), one map per record,
then the break byte `0xff` ([`finish!`](@ref)). It does not validate.
"""
mutable struct StreamEncoder
    started::Bool
    records::Int
end

StreamEncoder() = StreamEncoder(false, 0)

"""
    record!(enc, io, record)

Writes the next record (with the array header `0x9f` before the first).
"""
function record!(s::StreamEncoder, io::IO, r::Record)
    if !s.started
        write(io, 0x9f)
        s.started = true
    end
    s.records += 1
    encode_record(io, r, s.records)
    return nothing
end

"""
    finish!(enc, io)

Writes the break code `0xff` (and the header if no record was written).
"""
function finish!(s::StreamEncoder, io::IO)
    s.started || write(io, 0x9f)
    write(io, 0xff)
    return nothing
end

end # module Cbor
