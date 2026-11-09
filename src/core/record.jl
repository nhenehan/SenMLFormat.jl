# SenML records and packs as written, before resolution.
# https://www.rfc-editor.org/rfc/rfc8428#section-4

"""
    Value

The value of a record (one of `v`, `vs`, `vb`, `vd`,
[RFC 8428 section 4.2](https://www.rfc-editor.org/rfc/rfc8428#section-4.2)):
`Float64` for `v`, `String` for `vs`, `Bool` for `vb`, `Vector{UInt8}` for `vd`.
"""
const Value = Union{Float64,String,Bool,Vector{UInt8}}

# Values are equal when they have the same kind and are equal. (In Julia
# `true == 1.0`, but a `vb` is never the same as a `v`.)
same_value(a, b) = typeof(a) === typeof(b) && a == b
hash_value(v::Float64, h::UInt) = hash(v == 0 ? 0.0 : v, h)  # -0.0 == 0.0, so hash them alike
hash_value(v, h::UInt) = hash(v, h)

to_value(v::Bool) = v
to_value(v::Real) = Float64(v)
to_value(v::AbstractString) = String(v)
to_value(v::AbstractVector{UInt8}) = Vector{UInt8}(v)
to_value(v) = throw(ArgumentError("a SenML value is a number, string, Bool or bytes, not $(typeof(v))"))

value_label(::Float64) = L_V
value_label(::String) = L_VS
value_label(::Bool) = L_VB
value_label(::Vector{UInt8}) = L_VD

"""
    Extension(label, value)

A field with a label RFC 8428 does not register
([section 4.4](https://www.rfc-editor.org/rfc/rfc8428#section-4.4)).

Readers must ignore unknown labels. SenML.jl still keeps the ones whose value is a
single scalar (number, string, Bool or bytes), which is what the CDDL of
[section 11](https://www.rfc-editor.org/rfc/rfc8428#section-11) allows, so a pack
converted from one format to another keeps them. JSON and XML cannot tell a string
from base64 data, so an unknown label read from them is never bytes (and from XML
always a string).
"""
struct Extension
    label::String
    value::Value
    Extension(label::AbstractString, value) = new(String(label), to_value(value))
end

Extension(p::Pair) = Extension(p.first, p.second)

Base.:(==)(a::Extension, b::Extension) = a.label == b.label && same_value(a.value, b.value)
Base.hash(e::Extension, h::UInt) = hash_value(e.value, hash(e.label, hash(:Extension, h)))

"""
    is_base(e::Extension)

Base extensions (labels that start with `b`) apply to later records too.
"""
is_base(e::Extension) = is_base_label_text(e.label)

"""
    Record(; bn, bt, bu, bv, bs, bver, n, u, v, vs, vb, vd, s, t, ut, extensions)

One SenML record as written, base fields included. Every field is optional
(`nothing` when absent). Give at most one of `v`, `vs`, `vb`, `vd` (or `value`).
`extensions` is a vector of [`Extension`](@ref)s or `label => value` pairs.

```julia
Record(bn = "urn:dev:ow:10e2073a01080063:", n = "voltage", u = "V", v = 120.1)
```

Fields: `bn`, `bt`, `bu`, `bv`, `bs`, `bver`, `n`, `u`, `value`, `s`, `t`, `ut`,
`extensions`. Numbers are `Float64`, `bver` is `UInt64`, `value` is a
[`Value`](@ref).
"""
struct Record
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

opt_string(x) = x === nothing ? nothing : String(x)
opt_float(x) = x === nothing ? nothing : Float64(x)
opt_version(x) = x === nothing ? nothing : UInt64(x)
to_extension(e::Extension) = e
to_extension(e::Pair) = Extension(e)

function Record(;
    bn = nothing, bt = nothing, bu = nothing, bv = nothing, bs = nothing, bver = nothing,
    n = nothing, u = nothing, v = nothing, vs = nothing, vb = nothing, vd = nothing,
    value = nothing, s = nothing, t = nothing, ut = nothing, extensions = Extension[],
)
    given = (v !== nothing) + (vs !== nothing) + (vb !== nothing) + (vd !== nothing) +
        (value !== nothing)
    given > 1 && throw(ArgumentError("a record carries at most one of v, vs, vb, vd"))
    val::Union{Nothing,Value} =
        v !== nothing ? Float64(v) :
        vs !== nothing ? String(vs) :
        vb !== nothing ? Bool(vb) :
        vd !== nothing ? Vector{UInt8}(vd) :
        value !== nothing ? to_value(value) : nothing
    return Record(
        opt_string(bn), opt_float(bt), opt_string(bu), opt_float(bv), opt_float(bs),
        opt_version(bver), opt_string(n), opt_string(u), val, opt_float(s), opt_float(t),
        opt_float(ut), Extension[to_extension(e) for e in extensions],
    )
end

function Base.:(==)(a::Record, b::Record)
    return a.bn == b.bn && a.bt == b.bt && a.bu == b.bu && a.bv == b.bv && a.bs == b.bs &&
        a.bver == b.bver && a.n == b.n && a.u == b.u && same_value(a.value, b.value) &&
        a.s == b.s && a.t == b.t && a.ut == b.ut && a.extensions == b.extensions
end

function Base.hash(r::Record, h::UInt)
    h = hash(:Record, h)
    for f in (r.bn, r.bt, r.bu, r.bv, r.bs, r.bver, r.n, r.u, r.value, r.s, r.t, r.ut)
        h = hash_value(f, h)
    end
    return hash(r.extensions, h)
end

"True when the record carries any base field (registered or extension)."
has_base_fields(r::Record) =
    r.bn !== nothing || r.bt !== nothing || r.bu !== nothing || r.bv !== nothing ||
    r.bs !== nothing || r.bver !== nothing || any(is_base, r.extensions)

"True when the record carries any regular (non-base) field."
has_regular_fields(r::Record) =
    r.n !== nothing || r.u !== nothing || r.value !== nothing || r.s !== nothing ||
    r.t !== nothing || r.ut !== nothing || any(e -> !is_base(e), r.extensions)

"""
    is_base_only(r::Record)

A record with only base fields sets values for the records after it. It is not a
measurement itself (see the first record of the example in
[section 5.1.7](https://www.rfc-editor.org/rfc/rfc8428#section-5.1.7)).
"""
is_base_only(r::Record) = !has_regular_fields(r)

nonfinite(x) = x isa Float64 && !isfinite(x)

# The label of the first number in the record that is infinite or NaN, or
# `nothing`. Same order as rsenml's `Record::numbers`.
# (Each field is checked on its own, not in a loop over a tuple, which would box
# every field.)
function first_nonfinite(r::Record)::Union{Nothing,String}
    nonfinite(r.bt) && return label_text(L_BT)
    nonfinite(r.bv) && return label_text(L_BV)
    nonfinite(r.bs) && return label_text(L_BS)
    nonfinite(r.value) && return label_text(L_V)
    nonfinite(r.s) && return label_text(L_S)
    nonfinite(r.t) && return label_text(L_T)
    nonfinite(r.ut) && return label_text(L_UT)
    for e in r.extensions
        e.value isa Float64 && !isfinite(e.value) && return e.label
    end
    return nothing
end

"""
    Pack(records)
    Pack()

A SenML pack (or a complete SenSML stream): the records in order. A `Pack` is an
`AbstractVector{Record}`.
"""
struct Pack <: AbstractVector{Record}
    records::Vector{Record}
    Pack(records::Vector{Record}) = new(records)
end

Pack() = Pack(Record[])
Pack(records) = Pack(Record[r for r in records])

Base.size(p::Pack) = size(p.records)
Base.getindex(p::Pack, i::Int) = p.records[i]
Base.setindex!(p::Pack, r::Record, i::Int) = (p.records[i] = r; p)
Base.push!(p::Pack, r::Record) = (push!(p.records, r); p)
Base.IndexStyle(::Type{Pack}) = IndexLinear()
