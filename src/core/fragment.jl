# Record fragment identifiers: rec=3, rec=3-6, rec=19-*, rec=3-5,10,19-*.
# Positions start at 1.
# https://www.rfc-editor.org/rfc/rfc8428#section-9
#
# A selected record only keeps its meaning together with the base values of the
# records before it. So selection works on whole packs and gives positions. To use
# the selected records on their own, resolve the whole pack first. A range whose
# end comes before its start is refused.

"""
    RecordSelector

A parsed `rec=` fragment identifier
([section 9.1](https://www.rfc-editor.org/rfc/rfc8428#section-9.1) has
examples). `ranges` holds `(first, last)` pairs, 1-based; `last` is `typemax(Int)`
for `n-*`.

Make one with `parse(RecordSelector, "rec=3-5,10,19-*")` (a leading `#` is
allowed) or `tryparse`.
"""
struct RecordSelector
    ranges::Vector{Tuple{Int,Int}}
end

# A record position: one or more ASCII digits, not zero.
function fragment_position(s::AbstractString)::Int
    (isempty(s) || !all(c -> UInt8('0') <= c <= UInt8('9'), codeunits(s))) && return 0
    n = tryparse(Int, s)
    return n === nothing ? 0 : n
end

function Base.tryparse(::Type{RecordSelector}, fragment::AbstractString)
    f = startswith(fragment, '#') ? SubString(fragment, 2) : fragment
    startswith(f, "rec=") || return nothing
    ranges = Tuple{Int,Int}[]
    for item in split(SubString(f, 5), ',')
        dash = findfirst('-', item)
        if dash === nothing
            n = fragment_position(item)
            n == 0 && return nothing
            push!(ranges, (n, n))
        else
            a = fragment_position(SubString(item, 1, dash - 1))
            rest = SubString(item, dash + 1)
            a == 0 && return nothing
            if rest == "*"
                push!(ranges, (a, typemax(Int)))
            else
                b = fragment_position(rest)
                (b == 0 || b < a) && return nothing
                push!(ranges, (a, b))
            end
        end
    end
    return RecordSelector(ranges)
end

function Base.parse(::Type{RecordSelector}, fragment::AbstractString)
    s = tryparse(RecordSelector, fragment)
    s === nothing && throw(ArgumentError("not a SenML rec= fragment identifier: $(repr(fragment))"))
    return s
end

"""
    selects(sel::RecordSelector, position, len)

Whether the 1-based `position` is selected in a pack of `len` records.
"""
selects(sel::RecordSelector, position::Integer, len::Integer) =
    1 <= position <= len && any(r -> r[1] <= position <= r[2], sel.ranges)

"""
    selected(sel::RecordSelector, len) -> Vector{Int}

The selected 1-based positions in a pack of `len` records, ascending.
"""
selected(sel::RecordSelector, len::Integer) = [i for i in 1:len if selects(sel, i, len)]
