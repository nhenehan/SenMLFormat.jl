# Resolved records. A resolved record has every base value applied to it and an
# absolute time, so it makes sense on its own, outside its pack.
# https://www.rfc-editor.org/rfc/rfc8428#section-4.6
#
# How SenMLFormat reads the spec where it leaves room (the same as rsenml):
# - `bv` is added to a numeric `v` only. A record with no value field gets no
#   value (it is a sum-only record), even when a `bv` is in force.
# - The sum is `bs + s` when either one is present (section 4.5.4). So a `bs`
#   alone gives every later record a sum.
# - Times below 2^28 are relative to "now" (section 4.5.3). The caller gives
#   "now". Resolving such a time without it is an error.
# - Unknown base extensions cannot be resolved (section 4.6 leaves that to the spec
#   that defines them), so they are dropped. Regular extensions are kept.

"""
2^28 (268,435,456). Times at or above this are absolute (seconds since the Unix
epoch). Times below it are relative to "now"
([section 4.5.3](https://www.rfc-editor.org/rfc/rfc8428#section-4.5.3)).
"""
const ABSOLUTE_TIME_THRESHOLD = 268_435_456.0

"True when `t` is a relative time (below 2^28)."
is_relative_time(t::Real) = t < ABSOLUTE_TIME_THRESHOLD

"""
    ResolvedRecord

A record with every base value applied and an absolute time. Fields: `name`
(base name + name), `unit` (or the base unit in force), `value` (numbers with the
base value added), `sum` (base sum + sum, when either is present), `time`
(absolute, seconds since the Unix epoch), `update_time`, `version` (the pack's
version when it is not 10, as section 4.6 asks), `extensions` (regular ones only).
"""
struct ResolvedRecord
    name::String
    unit::Union{Nothing,String}
    value::Union{Nothing,Value}
    sum::Union{Nothing,Float64}
    time::Float64
    update_time::Union{Nothing,Float64}
    version::Union{Nothing,UInt64}
    extensions::Vector{Extension}
end

function Base.:(==)(a::ResolvedRecord, b::ResolvedRecord)
    return a.name == b.name && a.unit == b.unit && same_value(a.value, b.value) &&
        a.sum == b.sum && a.time == b.time && a.update_time == b.update_time &&
        a.version == b.version && a.extensions == b.extensions
end

function Base.hash(r::ResolvedRecord, h::UInt)
    h = hash(:ResolvedRecord, h)
    for f in (r.name, r.unit, r.value, r.sum, r.time, r.update_time, r.version)
        h = hash_value(f, h)
    end
    return hash(r.extensions, h)
end

"""
    to_record(r::ResolvedRecord) -> Record

The resolved record as a plain record (`bver` carries the version when it is not
10), so a resolved pack can be written in any format.
"""
to_record(r::ResolvedRecord) = Record(
    nothing, nothing, nothing, nothing, nothing, r.version, r.name, r.unit, r.value,
    r.sum, r.time, r.update_time, r.extensions,
)

"""
    Resolver(; now = nothing)

Applies base values one record at a time ([`resolve!`](@ref)). It works the same
for packs and for SenSML streams. `now` resolves relative times: the time the pack
(or, in a stream, the record) was sent, in seconds since the Unix epoch.
"""
mutable struct Resolver
    now::Union{Nothing,Float64}
    index::Int
    bn::Union{Nothing,String}
    bt::Union{Nothing,Float64}
    bu::Union{Nothing,String}
    bv::Union{Nothing,Float64}
    bs::Union{Nothing,Float64}
    version::UInt64
end

Resolver(; now::Union{Nothing,Real} = nothing) = Resolver(
    now === nothing ? nothing : Float64(now), 0, nothing, nothing, nothing, nothing,
    nothing, SUPPORTED_VERSION,
)

"""
    set_now!(r::Resolver, now)

Changes "now" for the records that follow. In a SenSML stream, "now" is set for
each record ([section 4.8](https://www.rfc-editor.org/rfc/rfc8428#section-4.8)).
"""
set_now!(r::Resolver, now::Union{Nothing,Real}) =
    (r.now = now === nothing ? nothing : Float64(now); r)

"""
    resolve!(res::Resolver, record) -> Union{ResolvedRecord,Nothing}

Applies the record's base fields, then resolves it. Returns `nothing` for a record
with only base fields. The record should have passed validation.

The steps follow [section 4.6](https://www.rfc-editor.org/rfc/rfc8428#section-4.6):
name = `bn` + `n`; unit = `u`, or else `bu`; value = `bv` + `v`; time = `bt` + `t`,
plus "now" when the total is relative.
"""
function resolve!(res::Resolver, r::Record)::Union{Nothing,ResolvedRecord}
    res.index += 1
    index = res.index
    # A base field applies to the record that holds it, as well as to later
    # records. So update the base values first.
    r.bn !== nothing && (res.bn = r.bn)
    r.bt !== nothing && (res.bt = r.bt)
    r.bu !== nothing && (res.bu = r.bu)
    r.bv !== nothing && (res.bv = r.bv)
    r.bs !== nothing && (res.bs = r.bs)
    r.bver !== nothing && (res.version = r.bver)
    is_base_only(r) && return nothing

    name = string(something(res.bn, ""), something(r.n, ""))
    v = r.value
    value = v isa Float64 ? something(res.bv, 0.0) + v : v
    sum = res.bs === nothing && r.s === nothing ? nothing :
        something(res.bs, 0.0) + something(r.s, 0.0)
    # A missing `bt` or `t` counts as zero. The test for "relative" is on the
    # total, since the spec warns that `bt + t` can cross 2^28.
    time = something(res.bt, 0.0) + something(r.t, 0.0)
    if is_relative_time(time)
        now = res.now
        now === nothing && throw(record_error(:RelativeTime, index))
        time += now
    end
    return ResolvedRecord(
        name,
        r.u !== nothing ? r.u : res.bu,
        value,
        sum,
        time,
        r.ut,
        res.version != SUPPORTED_VERSION ? res.version : nothing,
        Extension[e for e in r.extensions if !is_base(e)],
    )
end

"""
    resolve(pack; now = nothing) -> Vector{ResolvedRecord}

Validates the pack, resolves every record and sorts them by time, as
[section 4.6](https://www.rfc-editor.org/rfc/rfc8428#section-4.6) asks. The sort
is stable: records with equal times keep their order. `now` resolves relative
times; without it they are an error.
"""
function resolve(p::AbstractVector{Record}; now::Union{Nothing,Real} = nothing)
    validate(p)
    res = Resolver(; now)
    out = ResolvedRecord[]
    sizehint!(out, length(p))
    for r in p
        x = resolve!(res, r)
        x === nothing || push!(out, x)
    end
    sort!(out; by = x -> x.time, alg = MergeSort)
    return out
end
