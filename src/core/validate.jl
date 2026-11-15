# The rules of RFC 8428 section 4 that cover the whole pack, which no single
# field can check alone.
# https://www.rfc-editor.org/rfc/rfc8428#section-4
#
# How SenMLFormat reads the spec where it leaves room (the same as rsenml; see
# https://nhenehan.github.io/rsenml/rfc-choices.html):
# - A record with only base fields sets values for the records after it. It needs
#   no value or name (the first record of the example in section 5.1.7). Every
#   other record needs a value or a sum (section 4.2).
# - Version: each record's version is the last `bver` at or before it (10 when
#   there is none). All records must agree (section 4.4), so a `bver` that differs
#   from the version already in force is an error. Versions above 10 must not be
#   used. Versions below 10 are accepted (the RFC's own example uses 5).
# - Name rules apply to measurement records only: base name + name must not be
#   empty and must follow section 4.5.1.

"""
The SenML version SenMLFormat implements, which is also the default when there is no
`bver` ([section 4.1](https://www.rfc-editor.org/rfc/rfc8428#section-4.1)).
"""
const SUPPORTED_VERSION = UInt64(10)

# Characters allowed in a name (section 4.5.1): A-Za-z0-9:./_-
is_name_char(c::UInt8) =
    (UInt8('a') <= c <= UInt8('z')) | (UInt8('A') <= c <= UInt8('Z')) |
    (UInt8('0') <= c <= UInt8('9')) | (c == UInt8('-')) | (c == UInt8(':')) |
    (c == UInt8('.')) | (c == UInt8('/')) | (c == UInt8('_'))

# Characters a name may start with: A-Za-z0-9
is_name_start(c::UInt8) =
    (UInt8('a') <= c <= UInt8('z')) | (UInt8('A') <= c <= UInt8('Z')) |
    (UInt8('0') <= c <= UInt8('9'))

all_name_chars(s::AbstractString) = all(is_name_char, codeunits(s))

"""
    valid_name(base_name, name)

[Section 4.5.1](https://www.rfc-editor.org/rfc/rfc8428#section-4.5.1): the joined
name `base_name * name` must match `[A-Za-z0-9][A-Za-z0-9:./_-]*`.
"""
function valid_name(base_name::AbstractString, name::AbstractString)
    b = codeunits(base_name)
    n = codeunits(name)
    first = !isempty(b) ? b[1] : !isempty(n) ? n[1] : return false
    return is_name_start(first) && all(is_name_char, b) && all(is_name_char, n)
end

"""
    Validator(; registered_units = false)

Checks the records of a pack one at a time, so a SenSML stream can be checked as
its records arrive: [`check!`](@ref) each record, then [`finish`](@ref).

With `registered_units`, units (`u`, `bu`) must be in the SenML Units registry
(Table 6, [section 12.1](https://www.rfc-editor.org/rfc/rfc8428#section-12.1)).
RFC 8428 does not require it, so it is off by default.
"""
mutable struct Validator
    registered_units::Bool
    index::Int  # records checked so far
    version::UInt64  # the version in force; 0 before the first bver
    # What the name rule needs to know about the base name in force. It is worked
    # out once, when a record sets the base name, not again for each record.
    has_base::Bool
    base_empty::Bool
    base_valid::Bool  # its first character may start a name, and all may appear in one
end

Validator(; registered_units::Bool = false) =
    Validator(registered_units, 0, UInt64(0), false, false, false)

"""
    check!(v::Validator, record)

Checks the next record of the pack. Throws a [`SenMLError`](@ref).
"""
function check!(v::Validator, r::Record)
    v.index += 1
    index = v.index
    check_fields(v, r, index)
    check_version!(v, r, index)
    if r.bn !== nothing
        b = codeunits(r.bn)
        v.has_base = true
        v.base_empty = isempty(b)
        v.base_valid = !isempty(b) && is_name_start(b[1]) && all(is_name_char, b)
    end
    is_base_only(r) && return nothing
    r.value === nothing && r.s === nothing && throw(record_error(:MissingValue, index))
    r.n === nothing && !v.has_base && throw(record_error(:MissingName, index))
    n = r.n === nothing ? "" : r.n
    valid = if v.has_base && !v.base_empty
        # The name is bn * n. A non-empty bn holds the first character, and it was
        # checked when it was set. So n must only hold name characters.
        v.base_valid && all_name_chars(n)
    else
        # No base name, or an empty one: n alone must follow the whole rule.
        valid_name("", n)
    end
    valid || throw(record_error(:InvalidName, index))
    if r.u !== nothing && v.registered_units && lookup_unit(r.u) === nothing
        throw(record_error(:UnregisteredUnit, index))
    end
    return nothing
end

"""
    finish(v::Validator)

Ends the pack. It must have held at least one record (the CDDL is `[1* record]`,
[section 11](https://www.rfc-editor.org/rfc/rfc8428#section-11)).
"""
function finish(v::Validator)
    v.index == 0 && throw(SenMLError(:EmptyPack))
    return nothing
end

function check_fields(v::Validator, r::Record, index::Int)
    bad = first_nonfinite(r)
    bad === nothing || throw(record_error(:NonFinite, index, bad))
    ext = r.extensions
    for i in eachindex(ext)
        label = ext[i].label
        is_must_understand(label) && throw(record_error(:MustUnderstand, index, label))
        label_from_text(label) != 0 && throw(record_error(:InvalidLabel, index, label))
        for j in 1:(i-1)
            ext[j].label == label && throw(record_error(:DuplicateLabel, index, label))
        end
    end
    if r.bu !== nothing && v.registered_units && lookup_unit(r.bu) === nothing
        throw(record_error(:UnregisteredUnit, index))
    end
    return nothing
end

function check_version!(v::Validator, r::Record, index::Int)
    bver = r.bver
    bver === nothing && return nothing
    bver == 0 && throw(record_error(:InvalidVersion, index))
    bver > SUPPORTED_VERSION &&
        throw(SenMLError(:UnsupportedVersion; record = index, version = bver))
    # Records before the first bver had the default version (10).
    in_force = v.version != 0 ? v.version : index > 1 ? SUPPORTED_VERSION : bver
    in_force != bver && throw(record_error(:InconsistentVersion, index))
    v.version = bver
    return nothing
end

"""
    validate(pack; registered_units = false)

Checks the rules of
[RFC 8428 section 4](https://www.rfc-editor.org/rfc/rfc8428#section-4) (see
[`Validator`](@ref)). Throws a [`SenMLError`](@ref); returns `nothing`.
"""
function validate(p::AbstractVector{Record}; registered_units::Bool = false)
    v = Validator(; registered_units)
    for r in p
        check!(v, r)
    end
    return finish(v)
end
