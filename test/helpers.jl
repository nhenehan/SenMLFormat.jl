# Test vectors from the RFC text (spec/rfc8428.txt), so each one can be traced to
# the RFC. A port of rsenml-tests' src/lib.rs.

const SPEC = joinpath(@__DIR__, "..", "spec")

"The RFC text, with page breaks (footer, form feed, header) removed."
function rfc_text()
    out = IOBuffer()
    for line in eachline(joinpath(SPEC, "rfc8428.txt"))
        t = lstrip(line)
        (startswith(t, "Jennings, et al.") || startswith(t, "RFC 8428  ") || startswith(t, '\f')) && continue
        println(out, line)
    end
    return String(take!(out))
end

const RFC = rfc_text()

# A heading is a line that starts with a section number (digits and dots)
# followed by two spaces.
function heading(line)
    i = findfirst("  ", line)
    i === nothing && return nothing
    n = line[1:(first(i)-1)]
    (!isempty(n) && all(c -> isdigit(c) || c == '.', n)) || return nothing
    return rstrip(n, '.')
end

"The text of one section: from its heading to the next heading at column 0 that is not one of its subsections."
function section(text, number)
    out = IOBuffer()
    inside = false
    for line in split(text, '\n')
        h = heading(line)
        if h !== nothing
            inside && !startswith(h, number * ".") && break
            h == number && (inside = true)
        end
        inside && println(out, line)
    end
    return String(take!(out))
end

"""
Every JSON example of section 5.1, in order, as `(name, json, partial_stream)`. An
example starts at a line that is only `[` and ends at a line that is only `]` (or
`...`, the unfinished SenSML stream of 5.1.2, which is closed after its last
complete record). When a section has more than one, they are named `a`, `b`, ...
"""
function json_examples()
    out = NamedTuple{(:name, :json, :partial_stream),Tuple{String,String,Bool}}[]
    for sub in 1:7
        number = "5.1.$sub"
        arrays = Tuple{String,Bool}[]
        current = nothing
        for line in split(section(RFC, number), '\n')
            t = strip(line)
            if current === nothing
                t == "[" && (current = IOBuffer(); print(current, "[\n"))
            elseif t == "]" || t == "..."
                partial = t == "..."
                s = String(take!(current)) * "]"
                if partial
                    trimmed = rstrip(rstrip(rstrip(s, ']')), ',')
                    s = trimmed * "\n]"
                end
                push!(arrays, (s, partial))
                current = nothing
            else
                print(current, t, "\n")
            end
        end
        for (i, (json, partial)) in enumerate(arrays)
            suffix = length(arrays) > 1 ? string('a' + i - 1) : ""
            push!(out, (name = number * suffix, json = json, partial_stream = partial))
        end
    end
    return out
end

example_json(name) = only(e.json for e in json_examples() if e.name == name)
example(name) = SenML.Json.decode(example_json(name))

"Every `<sensml>` document in a section."
function xml_examples(number)
    out = String[]
    current = nothing
    for line in split(section(RFC, number), '\n')
        t = strip(line)
        startswith(t, "<sensml") && (current = IOBuffer())
        if current !== nothing
            print(current, t, "\n")
            if endswith(t, "</sensml>")
                push!(out, String(take!(current)))
                current = nothing
            end
        end
    end
    return out
end

"Every hex dump in a section (`0000 a0 30 ...` lines), as bytes."
function hex_dumps(number)
    out = Vector{UInt8}[]
    current = UInt8[]
    for line in split(section(RFC, number), '\n')
        fields = split(lstrip(line), ' ')
        off = fields[1]
        if length(off) == 4 && all(isxdigit, off)
            for f in fields[2:end]
                (length(f) == 2 && all(isxdigit, f)) || break
                push!(current, parse(UInt8, f; base = 16))
            end
        elseif !isempty(current)
            push!(out, current)
            current = UInt8[]
        end
    end
    isempty(current) || push!(out, current)
    return out
end

hex(s) = hex2bytes(filter(!isspace, s))

"Pack equality that treats numbers by bit pattern (so -0.0 != 0.0)."
function same_pack(a, b)
    a == b || return false
    bits(x::Float64) = reinterpret(UInt64, x)
    bits(x) = x
    for (x, y) in zip(a, b)
        for f in (:bt, :bv, :bs, :value, :s, :t, :ut)
            bits(getfield(x, f)) == bits(getfield(y, f)) || return false
        end
        all(bits(e.value) == bits(g.value) for (e, g) in zip(x.extensions, y.extensions)) || return false
    end
    return true
end

"""
The pack as EXI can carry it: EXI floats have no negative zero (an EXI Float's
mantissa is an EXI Integer, and EXI 7.1.5 codes a negative integer as its
magnitude minus one), so -0.0 comes back as 0.0.
"""
function exi_view(pack)
    z(x::Float64) = x == 0 ? 0.0 : x
    z(x) = x
    return Pack([Record(r.bn, z(r.bt), r.bu, z(r.bv), z(r.bs), r.bver, r.n, r.u, z(r.value), z(r.s),
        z(r.t), z(r.ut), r.extensions) for r in pack])
end

"The kind of SenMLError `f()` throws, or :ok."
function errkind(f)
    try
        f()
        return :ok
    catch e
        e isa SenMLError || rethrow()
        return e.kind
    end
end

"The SenMLError `f()` throws (or nothing)."
function err(f)
    try
        f()
        return nothing
    catch e
        e isa SenMLError || rethrow()
        return e
    end
end
