"""
    SenML.Json

The JSON format of SenML
([RFC 8428 section 5](https://www.rfc-editor.org/rfc/rfc8428#section-5)): media
types `application/senml+json` and, for streams, `application/sensml+json`.

```julia
pack = SenML.Json.decode(\"\"\"[{"bn":"urn:dev:ow:10e2073a01080063:","n":"voltage","u":"V","v":120.1},
                               {"n":"current","u":"A","v":1.2}]\"\"\")
SenML.Json.encode(pack)  # the same JSON, without whitespace
```

Reading checks the JSON grammar, label types, repeated labels, at most one value
per record, and labels ending in `_`. [`decode`](@ref) then validates the pack.
Unknown labels with string, number or boolean values are kept as `Extension`s;
other unknown labels are skipped.
"""
module Json

using ..SenML: SenML, Record, Pack, Extension, Value, SenMLError, Validator, check!,
    validate, syntax_error, incomplete, record_error, RecordBuilder, set!, extension!,
    skipped_extension, build, label_from_text, label_type, label_text, value_label,
    T_STRING, T_NUMBER, T_VERSION, T_BOOL, T_DATA, L_BVER, L_V, L_VS, L_VB, L_VD,
    parse_number, write_number, base64url_decode, base64url_encode
import ..SenML: finish

# How deep arrays and objects may nest inside the value of an unknown label before
# the reader gives up.
const MAX_DEPTH = 32

const Q = UInt8('"')
const BS = UInt8('\\')

is_ws(c::UInt8) = (c == 0x20) | (c == 0x09) | (c == 0x0a) | (c == 0x0d)
is_digit(c::UInt8) = UInt8('0') <= c <= UInt8('9')

#-------------------------------------------------------------------- the parser
#
# A pull parser over one record object, with the rules of nanojson (the JSON
# library rsenml uses), so that the same input gives the same error kind: the
# grammar of RFC 8259 (no leading zeros, digits after `.` and `e`, escapes,
# surrogate pairs, no raw control characters, UTF-8). Positions are 1-based
# indices into `b`; errors report 0-based byte offsets. `lim` is the last byte
# the parser may read (the end of the object when streaming).

mutable struct Parser{B<:AbstractVector{UInt8}}
    b::B
    pos::Int
    lim::Int
    scratch::Vector{UInt8}
end

serr(at::Int, reason::String) = syntax_error(:json, at - 1, reason)

function skip_ws!(p::Parser)
    while p.pos <= p.lim && is_ws(p.b[p.pos])
        p.pos += 1
    end
    return p.pos
end

# The first byte of the next token, or 0x00 at the end of the input.
function peek(p::Parser)::UInt8
    skip_ws!(p)
    return p.pos <= p.lim ? p.b[p.pos] : 0x00
end

# Value kinds, from the first byte (nanojson's lookahead).
const K_NONE = 0
const K_STRING = 1
const K_NUMBER = 2
const K_BOOL = 3
const K_NULL = 4
const K_ARRAY = 5
const K_OBJECT = 6

function kind_ahead(p::Parser)::Int
    c = peek(p)
    p.pos > p.lim && return K_NONE
    c == Q && return K_STRING
    (c == UInt8('-') || is_digit(c)) && return K_NUMBER
    (c == UInt8('t') || c == UInt8('f')) && return K_BOOL
    c == UInt8('n') && return K_NULL
    c == UInt8('[') && return K_ARRAY
    c == UInt8('{') && return K_OBJECT
    return K_NONE
end

# Expects one punctuation byte as the next token. Anything else, the end of the
# input included, is a syntax error (nanojson's `get_and_expect`).
function expect!(p::Parser, c::UInt8, what::String)
    skip_ws!(p)
    at = p.pos
    if at > p.lim || p.b[at] != c
        # nanojson reads the whole token before it looks at its type, so a string
        # cut off by the end of the input is reported as incomplete.
        at <= p.lim && p.b[at] == Q && string!(p)
        throw(serr(at, "expected " * what))
    end
    p.pos += 1
    return nothing
end

function starts_with(p::Parser, word::String)
    w = codeunits(word)
    p.pos + length(w) - 1 <= p.lim || return false
    for i in eachindex(w)
        p.b[p.pos+i-1] == w[i] || return false
    end
    return true
end

# A keyword: `true`, `false` or `null`. Returns 1, 0 or -1; anything else is a
# syntax error (an unexpected token, or not a value at all).
function keyword!(p::Parser)::Int
    skip_ws!(p)
    at = p.pos
    starts_with(p, "true") && (p.pos += 4; return 1)
    starts_with(p, "false") && (p.pos += 5; return 0)
    starts_with(p, "null") && (p.pos += 4; return -1)
    throw(serr(at, at > p.lim ? "unexpected end of a value" : "unexpected token"))
end

function boolean!(p::Parser)::Bool
    at = skip_ws!(p)
    k = keyword!(p)
    k < 0 && throw(serr(at, "expected a boolean"))
    return k == 1
end

# `null`, or the error for whatever is there instead (not a value, or another
# token).
function null!(p::Parser)
    at = skip_ws!(p)
    p.pos <= p.lim && p.b[p.pos] in (UInt8('{'), UInt8('}'), UInt8('['), UInt8(']'), UInt8(','), UInt8(':'), Q) &&
        throw(serr(at, "unexpected token"))
    keyword!(p) == -1 || throw(serr(at, "unexpected token"))
    return nothing
end

# A number: optional `-`, integer without leading zeros, optional fraction,
# optional exponent. Returns its text range.
function number!(p::Parser)::UnitRange{Int}
    skip_ws!(p)
    b = p.b
    start = p.pos
    i = start
    lim = p.lim
    i <= lim && b[i] == UInt8('-') && (i += 1)
    if i <= lim && b[i] == UInt8('0')
        i += 1
        i <= lim && is_digit(b[i]) && throw(serr(start, "leading zero"))
    elseif i <= lim && is_digit(b[i])
        while i <= lim && is_digit(b[i])
            i += 1
        end
    else
        throw(serr(start, "invalid number"))
    end
    if i <= lim && b[i] == UInt8('.')
        i += 1
        (i <= lim && is_digit(b[i])) || throw(serr(start, "invalid number"))
        while i <= lim && is_digit(b[i])
            i += 1
        end
    end
    if i <= lim && (b[i] == UInt8('e') || b[i] == UInt8('E'))
        i += 1
        i <= lim && (b[i] == UInt8('+') || b[i] == UInt8('-')) && (i += 1)
        (i <= lim && is_digit(b[i])) || throw(serr(start, "invalid number"))
        while i <= lim && is_digit(b[i])
            i += 1
        end
    end
    p.pos = i
    return start:(i-1)
end

# The bytes `b[r]` as a new Vector{UInt8}, for any byte vector.
function slice(b::AbstractVector{UInt8}, r::UnitRange{Int})::Vector{UInt8}
    out = Vector{UInt8}(undef, length(r))
    copyto!(out, 1, b, first(r), length(r))
    return out
end

text(p::Parser, r::UnitRange{Int}) = String(slice(p.b, r))

function hex4(p::Parser, i::Int)::Int
    i + 3 <= p.lim || return -1
    x = 0
    for j in i:(i+3)
        c = p.b[j]
        d = is_digit(c) ? c - UInt8('0') :
            UInt8('a') <= c <= UInt8('f') ? c - UInt8('a') + 10 :
            UInt8('A') <= c <= UInt8('F') ? c - UInt8('A') + 10 : return -1
        x = 16x + d
    end
    return x
end

function push_utf8!(out::Vector{UInt8}, cp::Int)
    if cp < 0x80
        push!(out, cp % UInt8)
    elseif cp < 0x800
        push!(out, (0xc0 | (cp >> 6)) % UInt8, (0x80 | (cp & 0x3f)) % UInt8)
    elseif cp < 0x10000
        push!(out, (0xe0 | (cp >> 12)) % UInt8, (0x80 | ((cp >> 6) & 0x3f)) % UInt8,
            (0x80 | (cp & 0x3f)) % UInt8)
    else
        push!(out, (0xf0 | (cp >> 18)) % UInt8, (0x80 | ((cp >> 12) & 0x3f)) % UInt8,
            (0x80 | ((cp >> 6) & 0x3f)) % UInt8, (0x80 | (cp & 0x3f)) % UInt8)
    end
end

# A string token (the next token must start with `"`, or it is a syntax error).
# The end of the input inside the string means the pack is incomplete.
function string!(p::Parser)::String
    skip_ws!(p)
    b = p.b
    start = p.pos
    (start <= p.lim && b[start] == Q) || throw(serr(start, "expected a string"))
    i = start + 1
    # Fast path: no escapes.
    while i <= p.lim
        c = b[i]
        (c == Q || c == BS || c < 0x20) && break
        i += 1
    end
    if i <= p.lim && b[i] == Q
        s = String(slice(b, (start+1):(i-1)))
        isvalid(s) || throw(serr(start, "invalid UTF-8"))
        p.pos = i + 1
        return s
    end
    out = p.scratch
    empty!(out)
    append!(out, view(b, (start+1):(i-1)))
    while true
        i > p.lim && throw(incomplete(:json))
        c = b[i]
        if c == Q
            p.pos = i + 1
            break
        elseif c == BS
            i += 1
            i > p.lim && throw(incomplete(:json))
            esc = b[i]
            i += 1
            if esc == UInt8('u')
                i + 3 > p.lim && throw(incomplete(:json))
                h = hex4(p, i)
                h < 0 && throw(serr(i, "invalid escape sequence"))
                i += 4
                if 0xd800 <= h <= 0xdbff
                    # A high surrogate must be followed by \uDC00..\uDFFF.
                    (i + 5 <= p.lim && b[i] == BS && b[i+1] == UInt8('u')) ||
                        throw(serr(i, "invalid escape sequence"))
                    i += 2
                    lo = hex4(p, i)
                    (lo >= 0 && 0xdc00 <= lo <= 0xdfff) || throw(serr(i, "invalid escape sequence"))
                    i += 4
                    push_utf8!(out, 0x10000 + ((h - 0xd800) << 10) + (lo - 0xdc00))
                elseif 0xdc00 <= h <= 0xdfff
                    throw(serr(i - 4, "invalid escape sequence"))  # a lone low surrogate
                else
                    push_utf8!(out, h)
                end
            else
                d = esc == Q ? Q : esc == BS ? BS : esc == UInt8('/') ? UInt8('/') :
                    esc == UInt8('b') ? 0x08 : esc == UInt8('t') ? 0x09 :
                    esc == UInt8('n') ? 0x0a : esc == UInt8('f') ? 0x0c :
                    esc == UInt8('r') ? 0x0d : throw(serr(i - 1, "invalid escape sequence"))
                push!(out, d)
            end
        elseif c < 0x20
            throw(serr(i, "unescaped control character"))
        else
            push!(out, c)
            i += 1
        end
    end
    s = String(copy(out))
    isvalid(s) || throw(serr(start, "invalid UTF-8"))
    return s
end

# Moves to the next member of an object: false at `}` (not read), true when a key
# follows (after reading the `,` between members). The end of the input here
# means the pack is incomplete.
function next_member!(p::Parser, first::Bool)::Bool
    skip_ws!(p)
    p.pos > p.lim && throw(incomplete(:json))
    c = p.b[p.pos]
    c == UInt8('}') && return false
    if !first
        c == UInt8(',') || throw(serr(p.pos, "expected , or }"))
        p.pos += 1
    end
    return true
end

# A member key and its colon.
function key!(p::Parser)::String
    k = string!(p)
    expect!(p, UInt8(':'), ":")
    return k
end

# The next item of an array: false at `]` (not read), true when an item follows.
function next_item!(p::Parser, first::Bool)::Bool
    c = peek(p)
    if !first && p.pos <= p.lim && c == UInt8(',')
        p.pos += 1
        return true
    end
    p.pos <= p.lim && c == UInt8(']') && return false
    first && return true
    throw(serr(p.pos, "expected , or ]"))
end

# Skips one value of any kind, checking its grammar.
function skip_value!(p::Parser, depth::Int)
    depth > MAX_DEPTH && throw(serr(p.pos, "value of an unknown label nested too deeply"))
    k = kind_ahead(p)
    if k == K_OBJECT
        p.pos += 1
        first = true
        while next_member!(p, first)
            key!(p)
            skip_value!(p, depth + 1)
            first = false
        end
        p.pos += 1
    elseif k == K_ARRAY
        p.pos += 1
        first = true
        while next_item!(p, first)
            skip_value!(p, depth + 1)
            first = false
        end
        p.pos += 1
    elseif k == K_STRING
        string!(p)
    elseif k == K_NUMBER
        number!(p)
    elseif k == K_BOOL
        boolean!(p)
    else
        null!(p)
    end
    return nothing
end

# The value of a registered label. It must have the JSON type of Table 2
# (section 5); `vd` is a base64url string. A value of the wrong kind is refused
# before it is read.
function field!(p::Parser, l::Int, index::Int)
    k = kind_ahead(p)
    if k == K_NONE
        null!(p)  # reports what is there
        throw(record_error(:WrongType, index, label_text(l)))
    end
    t = label_type(l)
    if t == T_STRING && k == K_STRING
        return string!(p)
    elseif t == T_NUMBER && k == K_NUMBER
        return parse_number(text(p, number!(p)))
    elseif t == T_VERSION && k == K_NUMBER
        # `bver` is an integer. Text like "5" reads as UInt64 straight away. Other
        # number text ("5.0", "5e0", "-1") goes through the double, and the record
        # builder decides whether it is a valid version.
        s = text(p, number!(p))
        u = all(is_digit, codeunits(s)) ? tryparse(UInt64, s) : nothing
        return u === nothing ? parse_number(s) : u
    elseif t == T_BOOL && k == K_BOOL
        return boolean!(p)
    elseif t == T_DATA && k == K_STRING
        d = base64url_decode(string!(p))
        d === nothing && throw(record_error(:InvalidBase64, index))
        return d
    end
    throw(record_error(:WrongType, index, label_text(l)))
end

# The value of an unknown label. A string, number or boolean is kept. Anything
# else (null, array, object) is skipped, but its grammar is still checked.
function extension_field!(p::Parser, b::RecordBuilder, label::String)
    k = kind_ahead(p)
    if k == K_STRING
        extension!(b, label, string!(p))
    elseif k == K_NUMBER
        extension!(b, label, parse_number(text(p, number!(p))))
    elseif k == K_BOOL
        extension!(b, label, boolean!(p))
    else
        skip_value!(p, 0)
        skipped_extension(b, label)
    end
    return nothing
end

# One record object (the next token must be `{`).
function parse_record!(p::Parser, index::Int)::Record
    expect!(p, UInt8('{'), "{")
    b = RecordBuilder(index)
    first = true
    while next_member!(p, first)
        key = key!(p)
        l = label_from_text(key)
        if l != 0
            set!(b, l, field!(p, l, index))
        else
            extension_field!(p, b, key)
        end
        first = false
    end
    p.pos += 1  # the closing brace
    return build(b)
end

#--------------------------------------------------------------- the outer array
#
# Where the reader is in `[ record, record, ... ]`: before `[` (START), after `[`
# (OPEN), after a record (RECORD), after `]` (DONE).

const ST_START = 0
const ST_OPEN = 1
const ST_RECORD = 2
const ST_DONE = 3

mutable struct Cursor
    pos::Int  # next unread byte (1-based)
    state::Int
    index::Int  # records read so far
    scratch::Vector{UInt8}
end

Cursor() = Cursor(1, ST_START, 0, UInt8[])

function skip_ws(b::AbstractVector{UInt8}, pos::Int)
    while pos <= length(b) && is_ws(b[pos])
        pos += 1
    end
    return pos
end

# Length of the JSON object at `b[start]` (a `{`) if all of it is there, else 0.
# It only tracks strings (so brackets inside strings do not count) and nesting
# depth; the parser checks everything else.
function object_end(b::AbstractVector{UInt8}, start::Int)::Int
    depth = 0
    in_string = false
    escaped = false
    for i in start:length(b)
        c = b[i]
        if in_string
            if escaped
                escaped = false
            elseif c == BS
                escaped = true
            elseif c == Q
                in_string = false
            end
            continue
        end
        if c == Q
            in_string = true
        elseif c == UInt8('{') || c == UInt8('[')
            depth += 1
        elseif c == UInt8('}') || c == UInt8(']')
            depth == 0 && return 0
            depth -= 1
            depth == 0 && return i
        end
    end
    return 0
end

# The result of a step: a record, the end of the pack, or (streaming only) "wait
# for more bytes".
const END = :end
const MORE = :more

# Moves over `b` by one record. With `partial`, running out of input gives MORE.
# Without it, running out is an Incomplete error. The cursor only moves past
# complete records, so a retry starts again at the same record.
function step!(c::Cursor, b::AbstractVector{UInt8}, partial::Bool)::Union{Record,Symbol}
    while true
        pos = skip_ws(b, c.pos)
        if pos > length(b)
            c.state == ST_DONE && return END
            partial && return MORE
            throw(incomplete(:json))
        end
        ch = b[pos]
        if c.state == ST_START
            ch == UInt8('[') || throw(serr(pos, "a SenML pack is a JSON array"))
            c.pos = pos + 1
            c.state = ST_OPEN
        elseif (c.state == ST_OPEN || c.state == ST_RECORD) && ch == UInt8(']')
            c.pos = pos + 1
            c.state = ST_DONE
            return END
        elseif c.state == ST_RECORD
            ch == UInt8(',') || throw(serr(pos, "expected , or ] after a record"))
            pos = skip_ws(b, pos + 1)
            if pos > length(b)
                partial && return MORE
                throw(incomplete(:json))
            end
            b[pos] == UInt8(']') && throw(serr(pos, "trailing comma"))
            return record!(c, b, pos, partial)
        elseif c.state == ST_OPEN
            return record!(c, b, pos, partial)
        else
            throw(serr(pos, "data after the end of the pack"))
        end
    end
end

function record!(c::Cursor, b::AbstractVector{UInt8}, start::Int, partial::Bool)
    lim = length(b)
    # When streaming, first make sure the whole object has arrived. Otherwise the
    # parser would report the cut-off object as an error. A record that is not an
    # object is left to the parser to report.
    if partial && b[start] == UInt8('{')
        lim = object_end(b, start)
        lim == 0 && return MORE
    end
    p = Parser(b, start, lim, c.scratch)
    r = parse_record!(p, c.index + 1)
    c.pos = p.pos
    c.state = ST_RECORD
    c.index += 1
    return r
end

# Only whitespace may follow the pack.
function finish_cursor(c::Cursor, b::AbstractVector{UInt8})
    pos = skip_ws(b, c.pos)
    c.state == ST_DONE || throw(incomplete(:json))
    pos <= length(b) && throw(serr(pos, "data after the end of the pack"))
    return nothing
end

#------------------------------------------------------------------- public API

bytes_of(input::AbstractVector{UInt8}) = input
bytes_of(input::AbstractString) = codeunits(input)

"""
    RecordReader(input)

Reads the records of a complete SenML JSON pack one at a time, without collecting
them. Records are checked as they are read (JSON form only); feed them to a
`Validator` for the rules of section 4. Iterate it, or call
[`next_record!`](@ref) until it returns `nothing`, then [`finish`](@ref).
"""
struct RecordReader{B<:AbstractVector{UInt8}}
    input::B
    cursor::Cursor
end

RecordReader(input) = (b = bytes_of(input); RecordReader{typeof(b)}(b, Cursor()))

"""
    next_record!(reader) -> Union{Record,Nothing}

The next record, or `nothing` after the end of the pack (for a stream decoder:
also when more bytes are needed).
"""
function next_record!(r::RecordReader)::Union{Nothing,Record}
    x = step!(r.cursor, r.input, false)
    return x isa Record ? x : nothing
end

"Byte offset (0-based) after the last record read."
position(r::RecordReader) = r.cursor.pos - 1

"""
    finish(reader)

Checks that the pack was closed and only whitespace follows.
"""
finish(r::RecordReader) = finish_cursor(r.cursor, r.input)

Base.IteratorSize(::Type{<:RecordReader}) = Base.SizeUnknown()
Base.eltype(::Type{<:RecordReader}) = Record
function Base.iterate(r::RecordReader, _ = nothing)
    x = next_record!(r)
    return x === nothing ? nothing : (x, nothing)
end

"""
    decode_unchecked(input) -> Pack

Reads a complete SenML JSON pack (bytes or a string), checking only the JSON form:
grammar, label types, repeated labels, at most one value, labels ending in `_`.
Use `validate` for the rules of section 4.
"""
function decode_unchecked(input)::Pack
    r = RecordReader(input)
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
    decode(input) -> Pack

Reads a complete SenML JSON pack (bytes or a string) and validates it
([RFC 8428 section 4](https://www.rfc-editor.org/rfc/rfc8428#section-4)). Throws
a `SenMLError`.
"""
function decode(input)::Pack
    p = decode_unchecked(input)
    validate(p)
    return p
end

"""
    StreamDecoder()
    StreamDecoder(; registered_units = false)

Decodes a SenSML JSON stream
([section 4.8](https://www.rfc-editor.org/rfc/rfc8428#section-4.8)) as its bytes
arrive. `push!` bytes, then call [`next_record!`](@ref) until it returns
`nothing`; each record is ready (and validated) as soon as its closing brace has
arrived. [`isfinished`](@ref) tells whether the closing `]` was read;
[`finish`](@ref) ends the stream.
"""
mutable struct StreamDecoder
    buf::Vector{UInt8}
    cursor::Cursor
    validator::Validator
end

StreamDecoder(; registered_units::Bool = false) =
    StreamDecoder(UInt8[], Cursor(), Validator(; registered_units))

function Base.push!(d::StreamDecoder, bytes)
    # Drop the bytes already read once they fill more than half of the buffer
    # (and more than 4096 bytes), so the buffer does not grow forever.
    read = d.cursor.pos - 1
    if read > 4096 && read * 2 > length(d.buf)
        deleteat!(d.buf, 1:read)
        d.cursor.pos = 1
    end
    append!(d.buf, bytes_of(bytes))
    return d
end

function next_record!(d::StreamDecoder)::Union{Nothing,Record}
    x = step!(d.cursor, d.buf, true)
    x isa Record || return nothing
    check!(d.validator, x)
    return x
end

"The closing `]` has been read."
isfinished(d::StreamDecoder) = d.cursor.state == ST_DONE

"""
    finish(d::StreamDecoder)

Ends the stream. It must be closed, hold at least one record, and have only
whitespace after it.
"""
function finish(d::StreamDecoder)
    finish_cursor(d.cursor, d.buf)
    return finish(d.validator)
end

#----------------------------------------------------------------------- writing
#
# Fields are written in the order of the RFC's own examples (bn bt bu bv bs bver
# n u t ut s v vs vb vd), with extensions after them. Numbers use the shortest
# text that reads back as the same double. Data Values are base64url without
# padding. No whitespace is written. Strings are escaped the way nanojson does
# it: `"` `\` and \b \t \n \f \r by name, other control characters and DEL as
# \u00XX, everything else (including `/` and non-ASCII UTF-8) as is.

const HEX = codeunits("0123456789abcdef")

function utf8_len(c::UInt8)::Int
    c & 0x80 == 0 && return 1
    c & 0xe0 == 0xc0 && return 2
    c & 0xf0 == 0xe0 && return 3
    c & 0xf8 == 0xf0 && return 4
    return 1
end

function write_escaped(io::IO, s::AbstractString)
    b = codeunits(s)
    write(io, Q)
    i = 1
    n = length(b)
    while i <= n
        c = b[i]
        if c == Q
            write(io, BS, Q)
            i += 1
        elseif c == BS
            write(io, BS, BS)
            i += 1
        elseif c == 0x08
            write(io, BS, UInt8('b'))
            i += 1
        elseif c == 0x09
            write(io, BS, UInt8('t'))
            i += 1
        elseif c == 0x0a
            write(io, BS, UInt8('n'))
            i += 1
        elseif c == 0x0c
            write(io, BS, UInt8('f'))
            i += 1
        elseif c == 0x0d
            write(io, BS, UInt8('r'))
            i += 1
        elseif 0x20 <= c <= 0x7e
            start = i
            while i <= n && 0x20 <= b[i] <= 0x7e && b[i] != Q && b[i] != BS
                i += 1
            end
            write(io, view(b, start:(i-1)))
        else
            len = utf8_len(c)
            valid = len > 1 && i + len - 1 <= n && all(j -> b[j] & 0xc0 == 0x80, (i+1):(i+len-1))
            if valid
                write(io, view(b, i:(i+len-1)))
                i += len
            else
                # Not UTF-8 (or a control character or DEL): escape this byte.
                write(io, BS, UInt8('u'), UInt8('0'), UInt8('0'), HEX[(c>>4)+1], HEX[(c&0x0f)+1])
                i += 1
            end
        end
    end
    write(io, Q)
    return nothing
end

function write_member(io::IO, first::Bool, label::AbstractString)
    first || write(io, UInt8(','))
    write_escaped(io, label)
    write(io, UInt8(':'))
    return false
end

function write_json_number(io::IO, v::Float64, label::AbstractString, index::Int)
    isfinite(v) || throw(record_error(:NonFinite, index, label))
    write_number(io, v)
    return nothing
end

# A string or number field, when present. Returns the new `first`.
write_field(::IO, first::Bool, ::String, ::Nothing, ::Int) = first
function write_field(io::IO, first::Bool, label::String, x::String, ::Int)
    write_member(io, first, label)
    write_escaped(io, x)
    return false
end
function write_field(io::IO, first::Bool, label::String, x::Float64, index::Int)
    write_member(io, first, label)
    write_json_number(io, x, label, index)
    return false
end

function write_value(io::IO, v::Value, label::AbstractString, index::Int)
    if v isa Float64
        write_json_number(io, v, label, index)
    elseif v isa String
        write_escaped(io, v)
    elseif v isa Bool
        write(io, v ? "true" : "false")
    else
        write(io, Q, base64url_encode(v), Q)
    end
    return nothing
end

"""
    encode_record(io, record, index)

Writes one record object (for writing a SenSML stream one piece at a time; see
[`StreamEncoder`](@ref)). `index` (1-based) is only used in error reports.
"""
function encode_record(io::IO, r::Record, index::Integer = 1)
    index = Int(index)
    write(io, UInt8('{'))
    first = true
    # One call per field, not a loop over a tuple: the fields have different
    # types, and a loop over them would box each one.
    first = write_field(io, first, "bn", r.bn, index)
    first = write_field(io, first, "bt", r.bt, index)
    first = write_field(io, first, "bu", r.bu, index)
    first = write_field(io, first, "bv", r.bv, index)
    first = write_field(io, first, "bs", r.bs, index)
    if r.bver !== nothing
        first = write_member(io, first, "bver")
        print(io, r.bver)
    end
    first = write_field(io, first, "n", r.n, index)
    first = write_field(io, first, "u", r.u, index)
    first = write_field(io, first, "t", r.t, index)
    first = write_field(io, first, "ut", r.ut, index)
    first = write_field(io, first, "s", r.s, index)
    v = r.value
    if v !== nothing
        label = label_text(value_label(v))
        first = write_member(io, first, label)
        write_value(io, v, label, index)
    end
    for e in r.extensions
        first = write_member(io, first, e.label)
        write_value(io, e.value, e.label, index)
    end
    write(io, UInt8('}'))
    return nothing
end

"""
    encode_unchecked(pack) -> Vector{UInt8}

Writes a pack as it is, without validating. Infinite and NaN numbers are still
refused, because JSON has no way to write them.
"""
function encode_unchecked(p::AbstractVector{Record})::Vector{UInt8}
    io = IOBuffer()
    write(io, UInt8('['))
    for (i, r) in enumerate(p)
        i > 1 && write(io, UInt8(','))
        encode_record(io, r, i)
    end
    write(io, UInt8(']'))
    return take!(io)
end

"""
    encode(pack) -> Vector{UInt8}

Validates a pack ([RFC 8428 section 4](https://www.rfc-editor.org/rfc/rfc8428#section-4))
and writes it as SenML JSON.
"""
function encode(p::AbstractVector{Record})::Vector{UInt8}
    validate(p)
    return encode_unchecked(p)
end

"""
    StreamEncoder()

Writes a SenSML JSON stream one piece at a time: [`record!`](@ref) writes `[`
before the first record and `,` before the others; [`finish!`](@ref) writes `]`
(or `[]` if no record was written). It does not validate; run a `Validator` next
to it if needed.
"""
mutable struct StreamEncoder
    records::Int
end

StreamEncoder() = StreamEncoder(0)

"""
    record!(enc, io, record)

Writes the next record of the stream.
"""
function record!(s::StreamEncoder, io::IO, r::Record)
    write(io, s.records == 0 ? UInt8('[') : UInt8(','))
    s.records += 1
    encode_record(io, r, s.records)
    return nothing
end

"""
    finish!(enc, io)

Writes the end of the stream.
"""
function finish!(s::StreamEncoder, io::IO)
    s.records == 0 && write(io, UInt8('['))
    write(io, UInt8(']'))
    return nothing
end

end # module Json
