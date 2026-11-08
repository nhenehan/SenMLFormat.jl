# Builds a record one field at a time. Every reader shares it.
#
# The checks that belong to reading one record (rather than to checking a whole
# pack) live here, so every format applies them the same way: each label at most
# once, at most one value label, numbers finite, and labels ending in `_` refused.
# https://www.rfc-editor.org/rfc/rfc8428#section-4.4
#
# A decoded field value is a `FieldValue`: a String, a Float64 (any JSON number,
# any CBOR float or decimal fraction), a UInt64 (a CBOR unsigned integer, also good
# where a number is wanted), a Bool, or bytes (already decoded from base64url when
# the format uses text).

const FieldValue = Union{String,Float64,UInt64,Bool,Vector{UInt8}}

mutable struct RecordBuilder
    index::Int  # 1-based position in the pack, for error reports
    seen::UInt16  # one bit per registered label
    bn::Union{Nothing,String}
    bt::Union{Nothing,Float64}
    bu::Union{Nothing,String}
    bv::Union{Nothing,Float64}
    bs::Union{Nothing,Float64}
    bver::Union{Nothing,UInt64}
    n::Union{Nothing,String}
    u::Union{Nothing,String}
    value::Union{Nothing,Value}
    s::Union{Nothing,Float64}
    t::Union{Nothing,Float64}
    ut::Union{Nothing,Float64}
    extensions::Vector{Extension}
end

RecordBuilder(index::Integer) = RecordBuilder(
    Int(index), 0x0000, nothing, nothing, nothing, nothing, nothing, nothing, nothing,
    nothing, nothing, nothing, nothing, nothing, Extension[],
)

build(b::RecordBuilder) =
    Record(b.bn, b.bt, b.bu, b.bv, b.bs, b.bver, b.n, b.u, b.value, b.s, b.t, b.ut, b.extensions)

wrong_type(b::RecordBuilder, l::Int) = record_error(:WrongType, b.index, label_text(l))

field_string(b::RecordBuilder, l::Int, v::FieldValue) =
    v isa String ? v : throw(wrong_type(b, l))

function field_number(b::RecordBuilder, l::Int, v::FieldValue)::Float64
    x = v isa Float64 ? v : v isa UInt64 ? Float64(v) : throw(wrong_type(b, l))
    isfinite(x) || throw(record_error(:NonFinite, b.index, label_text(l)))
    return x
end

# `bver` from a number. A JSON number counts when it is a whole number from 0 to
# 2^53 (9,007,199,254,740,992), the range where every integer fits a double
# exactly. Zero passes here; the validator refuses it later.
function field_version(b::RecordBuilder, v::FieldValue)::UInt64
    v isa UInt64 && return v
    if v isa Float64
        0.0 <= v <= 9.007199254740992e15 && v == trunc(v) && return UInt64(v)
        throw(record_error(:InvalidVersion, b.index))
    end
    throw(wrong_type(b, L_BVER))
end

function set_value!(b::RecordBuilder, v::Value)
    b.value === nothing || throw(record_error(:MultipleValues, b.index))
    b.value = v
    return nothing
end

"""
    set!(b, label, value)

Sets a registered label. The value must have the label's type. A `UInt64` is
accepted for numbers, and a `Float64` holding a whole number for `bver` (JSON has
one number type).
"""
function set!(b::RecordBuilder, l::Int, v::FieldValue)
    bit = UInt16(1) << (l - 1)
    b.seen & bit != 0 && throw(record_error(:DuplicateLabel, b.index, label_text(l)))
    b.seen |= bit
    if l == L_BN
        b.bn = field_string(b, l, v)
    elseif l == L_BU
        b.bu = field_string(b, l, v)
    elseif l == L_N
        b.n = field_string(b, l, v)
    elseif l == L_U
        b.u = field_string(b, l, v)
    elseif l == L_BT
        b.bt = field_number(b, l, v)
    elseif l == L_BV
        b.bv = field_number(b, l, v)
    elseif l == L_BS
        b.bs = field_number(b, l, v)
    elseif l == L_S
        b.s = field_number(b, l, v)
    elseif l == L_T
        b.t = field_number(b, l, v)
    elseif l == L_UT
        b.ut = field_number(b, l, v)
    elseif l == L_BVER
        b.bver = field_version(b, v)
    elseif l == L_V
        set_value!(b, field_number(b, l, v))
    elseif l == L_VS
        set_value!(b, field_string(b, l, v))
    elseif l == L_VB
        v isa Bool || throw(wrong_type(b, l))
        set_value!(b, v)
    else # L_VD
        v isa Vector{UInt8} || throw(wrong_type(b, l))
        set_value!(b, v)
    end
    return nothing
end

"""
    extension!(b, label, value)

Adds a field whose label is not registered. Labels ending in `_` fail
([section 4.4](https://www.rfc-editor.org/rfc/rfc8428#section-4.4)). So does a
label already given, or the name of a registered label.
"""
function extension!(b::RecordBuilder, label::String, v::FieldValue)
    is_must_understand(label) && throw(record_error(:MustUnderstand, b.index, label))
    if label_from_text(label) != 0 || any(e -> e.label == label, b.extensions)
        throw(record_error(:DuplicateLabel, b.index, label))
    end
    if v isa Float64 && !isfinite(v)
        throw(record_error(:NonFinite, b.index, label))
    end
    push!(b.extensions, Extension(label, v isa UInt64 ? Float64(v) : v))
    return nothing
end

"""
    skipped_extension(b, label)

The checks of [`extension!`](@ref) for a field whose value is skipped (an array or
map, which the CDDL of section 11 does not allow). Must-understand labels still
fail; everything else is ignored.
"""
function skipped_extension(b::RecordBuilder, label::AbstractString)
    is_must_understand(label) && throw(record_error(:MustUnderstand, b.index, label))
    return nothing
end
