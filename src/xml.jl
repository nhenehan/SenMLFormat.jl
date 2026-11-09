"""
    SenML.Xml

The XML format of SenML
([RFC 8428 section 7](https://www.rfc-editor.org/rfc/rfc8428#section-7)): media
types `application/senml+xml` and `application/sensml+xml`.

The document is a `sensml` element in the namespace `urn:ietf:params:xml:ns:senml`,
holding one `senml` element per record. Their attributes without a prefix are the
fields (Table 5).

Reading:
- Only UTF-8 is accepted (section 7). A DTD is refused (so no entity expansion).
- Whitespace, comments and processing instructions may appear between records.
  Other text and child elements may not.
- Attributes in other namespaces (`xml:lang`, `xmlns:*`, foreign ones) are ignored.
  Unknown attributes without a prefix are extensions (string values).
- `INF`, `-INF` and `NaN` are valid `xs:double` values but not SenML numbers.

Writing gives `<sensml xmlns="urn:ietf:params:xml:ns:senml">` with one empty
`<senml .../>` element per record, attributes in the order of the RFC's examples,
no XML declaration and no whitespace.
"""
module Xml

using ..SenML: SenML, Record, Pack, Extension, Value, SenMLError, validate,
    syntax_error, incomplete, record_error, RecordBuilder, set!, extension!, build,
    label_from_text, label_type, label_text, value_label, T_STRING, T_NUMBER,
    T_VERSION, T_BOOL, T_DATA, parse_number, write_number, base64url_decode,
    write_base64url!, base64url_length, XML_NAMESPACE
import ..SenML: finish

const XML_PREFIX_NAMESPACE = "http://www.w3.org/XML/1998/namespace"

#----------------------------------------------------------------- the tokenizer
#
# A port of the parts of xmlparser 0.13 (the tokenizer rsenml uses) that a SenML
# document can meet, with the same rules, so the same input gives the same error
# kind: XML names (https://www.w3.org/TR/xml/#NT-Name), legal characters
# (https://www.w3.org/TR/xml/#NT-Char), no `<` in attribute values, no `--` in
# comments, no `]]>` in text, the XML declaration only at the very start. Like
# xmlparser, an error is reported at the start of the token it was found in.
# Positions are 1-based byte indices into the text; errors give 0-based offsets.

# Character classes.
is_space(b::UInt8) = (b == 0x20) | (b == 0x09) | (b == 0x0a) | (b == 0x0d)
is_ascii_name(b::UInt8) =
    (UInt8('A') <= b <= UInt8('Z')) | (UInt8('a') <= b <= UInt8('z')) |
    (UInt8('0') <= b <= UInt8('9')) | (b == UInt8(':')) | (b == UInt8('_')) |
    (b == UInt8('-')) | (b == UInt8('.'))

# XML 1.0 NameStartChar (https://www.w3.org/TR/xml/#NT-NameStartChar), with `:`.
function is_name_start(c::UInt32)
    c <= 128 && return (UInt32('A') <= c <= UInt32('Z')) | (UInt32('a') <= c <= UInt32('z')) |
        (c == UInt32(':')) | (c == UInt32('_'))
    return (0xc0 <= c <= 0xd6) | (0xd8 <= c <= 0xf6) | (0xf8 <= c <= 0x2ff) |
        (0x370 <= c <= 0x37d) | (0x37f <= c <= 0x1fff) | (0x200c <= c <= 0x200d) |
        (0x2070 <= c <= 0x218f) | (0x2c00 <= c <= 0x2fef) | (0x3001 <= c <= 0xd7ff) |
        (0xf900 <= c <= 0xfdcf) | (0xfdf0 <= c <= 0xfffd) | (0x10000 <= c <= 0xeffff)
end

# XML 1.0 NameChar (https://www.w3.org/TR/xml/#NT-NameChar).
function is_name_char(c::UInt32)
    c <= 128 && return c < 128 && is_ascii_name(c % UInt8)
    return c == 0xb7 || (0x300 <= c <= 0x36f) || (0x203f <= c <= 0x2040) || is_name_start(c)
end

# XML 1.0 Char (https://www.w3.org/TR/xml/#NT-Char). The text is valid UTF-8, so
# surrogates are already ruled out.
is_xml_char(c::UInt32) = c < 0x20 ? is_space(c % UInt8) : (c != 0xfffe) & (c != 0xffff)

const TK_DECL = 1      # range a: the encoding (empty when absent)
const TK_PI = 2
const TK_COMMENT = 3
const TK_START = 4     # range p: prefix, a: local name
const TK_ATTR = 5      # range p: prefix, a: local name, v: raw value
const TK_OPEN_END = 6  # `>` of a start tag
const TK_EMPTY_END = 7 # `/>`
const TK_CLOSE = 8     # `</p:a>`
const TK_TEXT = 9      # range a: the text
const TK_CDATA = 10    # range a: the content

struct Token
    kind::Int
    start::Int
    p::UnitRange{Int}
    a::UnitRange{Int}
    v::UnitRange{Int}
end

Token(kind::Int, start::Int) = Token(kind, start, 1:0, 1:0, 1:0)

# Tokenizer states (xmlparser's, without the DTD ones: a DTD is refused).
const S_DECLARATION = 0
const S_AFTER_DECLARATION = 1
const S_AFTER_DTD = 2
const S_ELEMENTS = 3
const S_ATTRIBUTES = 4
const S_AFTER_ELEMENTS = 5

mutable struct Tokenizer
    s::String
    b::Base.CodeUnits{UInt8,String}
    n::Int
    pos::Int
    state::Int
    depth::Int
end

function Tokenizer(s::String)
    b = codeunits(s)
    pos = 1
    # Skip a UTF-8 byte order mark.
    length(b) >= 3 && b[1] == 0xef && b[2] == 0xbb && b[3] == 0xbf && (pos = 4)
    return Tokenizer(s, b, length(b), pos, S_DECLARATION, 0)
end

# An error at `pos`. Past the end of the text it means the document is cut off.
xml_error(t::Tokenizer, pos::Int, reason::String) =
    pos > t.n ? incomplete(:xml) : syntax_error(:xml, pos - 1, reason)

at_end(t::Tokenizer) = t.pos > t.n
cur(t::Tokenizer) = t.b[t.pos]

function starts_with(t::Tokenizer, w::String)
    c = codeunits(w)
    t.pos + length(c) - 1 <= t.n || return false
    for i in eachindex(c)
        t.b[t.pos+i-1] == c[i] || return false
    end
    return true
end

function skip_spaces!(t::Tokenizer)
    while t.pos <= t.n && is_space(t.b[t.pos])
        t.pos += 1
    end
end

starts_with_space(t::Tokenizer) = t.pos <= t.n && is_space(t.b[t.pos])

# The character at `pos` and the position after it.
function char_at(t::Tokenizer, pos::Int)
    c, next = iterate(t.s, pos)::Tuple{Char,Int}
    return UInt32(c), next
end

# Advances over characters while `keep(pos, c)` holds. Every character passed over
# (and the one that stops it) must be an XML character; otherwise the error is
# reported at `err_at`.
function consume_chars!(keep, t::Tokenizer, err_at::Int, reason::String)
    start = t.pos
    while t.pos <= t.n
        c, next = char_at(t, t.pos)
        is_xml_char(c) || throw(xml_error(t, err_at, "character not allowed in XML"))
        keep(t.pos, c) || break
        t.pos = next
    end
    return start:(t.pos-1)
end

function skip_string!(t::Tokenizer, w::String, err_at::Int, reason::String)
    starts_with(t, w) || throw(xml_error(t, err_at, reason))
    t.pos += ncodeunits(w)
    return nothing
end

function consume_byte!(t::Tokenizer, c::UInt8, err_at::Int, reason::String)
    (t.pos <= t.n && t.b[t.pos] == c) || throw(xml_error(t, err_at, reason))
    t.pos += 1
    return nothing
end

function consume_quote!(t::Tokenizer, err_at::Int, reason::String)::UInt8
    t.pos <= t.n || throw(xml_error(t, err_at, reason))
    q = t.b[t.pos]
    (q == UInt8('"') || q == UInt8('\'')) || throw(xml_error(t, err_at, reason))
    t.pos += 1
    return q
end

function consume_eq!(t::Tokenizer, err_at::Int, reason::String)
    skip_spaces!(t)
    consume_byte!(t, UInt8('='), err_at, reason)
    skip_spaces!(t)
end

# A Name: a name-start character, then name characters.
function consume_name!(t::Tokenizer, err_at::Int, reason::String)::UnitRange{Int}
    start = t.pos
    if t.pos <= t.n
        c, next = char_at(t, t.pos)
        is_name_start(c) || throw(xml_error(t, err_at, reason))
        t.pos = next
    end
    while t.pos <= t.n
        c, next = char_at(t, t.pos)
        is_name_char(c) || break
        t.pos = next
    end
    t.pos == start && throw(xml_error(t, err_at, reason))
    return start:(t.pos-1)
end

# A qualified name `prefix:local` (one colon at most); both parts must start with
# a name-start character.
function consume_qname!(t::Tokenizer, err_at::Int)::Tuple{UnitRange{Int},UnitRange{Int}}
    start = t.pos
    colon = 0
    while t.pos <= t.n
        b = t.b[t.pos]
        if b < 0x80
            if b == UInt8(':')
                colon == 0 || throw(xml_error(t, err_at, "invalid name"))
                colon = t.pos
                t.pos += 1
            elseif is_ascii_name(b)
                t.pos += 1
            else
                break
            end
        else
            c, next = char_at(t, t.pos)
            is_name_char(c) || break
            t.pos = next
        end
    end
    prefix = colon == 0 ? (start:(start-1)) : (start:(colon-1))
    local_ = colon == 0 ? (start:(t.pos-1)) : ((colon+1):(t.pos-1))
    isempty(prefix) || is_name_start(char_at(t, first(prefix))[1]) ||
        throw(xml_error(t, err_at, "invalid name"))
    (!isempty(local_) && is_name_start(char_at(t, first(local_))[1])) ||
        throw(xml_error(t, err_at, "invalid name"))
    return prefix, local_
end

# '<?xml' VersionInfo EncodingDecl? SDDecl? S? '?>'
function parse_declaration!(t::Tokenizer)::Token
    start = t.pos
    bad = "invalid XML declaration"
    t.pos += 6
    skip_spaces!(t)
    skip_string!(t, "version", start, bad)
    consume_eq!(t, start, bad)
    q = consume_quote!(t, start, bad)
    skip_string!(t, "1.", start, bad)
    while t.pos <= t.n && UInt8('0') <= t.b[t.pos] <= UInt8('9')
        t.pos += 1
    end
    consume_byte!(t, q, start, bad)
    decl_spaces!(t, start)
    encoding = 1:0
    if starts_with(t, "encoding")
        t.pos += 8
        consume_eq!(t, start, bad)
        q = consume_quote!(t, start, bad)
        e = t.pos
        while t.pos <= t.n && (is_ascii_name(t.b[t.pos]) && t.b[t.pos] != UInt8(':'))
            t.pos += 1
        end
        encoding = e:(t.pos-1)
        consume_byte!(t, q, start, bad)
        decl_spaces!(t, start)
    end
    if starts_with(t, "standalone")
        t.pos += 10
        consume_eq!(t, start, bad)
        q = consume_quote!(t, start, bad)
        r = consume_name!(t, start, bad)
        v = String(t.b[r])
        (v == "yes" || v == "no") || throw(xml_error(t, start, bad))
        consume_byte!(t, q, start, bad)
    end
    skip_spaces!(t)
    skip_string!(t, "?>", start, bad)
    return Token(TK_DECL, start, 1:0, encoding, 1:0)
end

function decl_spaces!(t::Tokenizer, start::Int)
    if starts_with_space(t)
        skip_spaces!(t)
    elseif !starts_with(t, "?>") && !at_end(t)
        throw(xml_error(t, start, "invalid XML declaration"))
    end
end

# '<!--' ((Char - '-') | ('-' (Char - '-')))* '-->'
function parse_comment!(t::Tokenizer)::Token
    start = t.pos
    bad = "invalid comment"
    t.pos += 4
    text = consume_chars!(t, start, bad) do pos, c
        !(c == UInt32('-') && starts_with_at(t, pos, "-->"))
    end
    skip_string!(t, "-->", start, bad)
    s = view(t.b, text)
    for i in 1:(length(s)-1)
        s[i] == UInt8('-') && s[i+1] == UInt8('-') && throw(xml_error(t, start, bad))
    end
    !isempty(s) && s[end] == UInt8('-') && throw(xml_error(t, start, bad))
    return Token(TK_COMMENT, start)
end

function starts_with_at(t::Tokenizer, pos::Int, w::String)
    c = codeunits(w)
    pos + length(c) - 1 <= t.n || return false
    for i in eachindex(c)
        t.b[pos+i-1] == c[i] || return false
    end
    return true
end

# '<?' PITarget (S (Char* - (Char* '?>' Char*)))? '?>'
function parse_pi!(t::Tokenizer)::Token
    start = t.pos
    bad = "invalid processing instruction"
    t.pos += 2
    consume_name!(t, start, bad)
    skip_spaces!(t)
    consume_chars!(t, start, bad) do pos, c
        !(c == UInt32('?') && starts_with_at(t, pos, "?>"))
    end
    skip_string!(t, "?>", start, bad)
    return Token(TK_PI, start)
end

# '<![CDATA[' (Char* - (Char* ']]>' Char*)) ']]>'
function parse_cdata!(t::Tokenizer)::Token
    start = t.pos
    bad = "invalid CDATA section"
    t.pos += 9
    text = consume_chars!(t, start, bad) do pos, c
        !(c == UInt32(']') && starts_with_at(t, pos, "]]>"))
    end
    skip_string!(t, "]]>", start, bad)
    return Token(TK_CDATA, start, 1:0, text, 1:0)
end

function parse_element_start!(t::Tokenizer)::Token
    start = t.pos
    t.pos += 1
    p, a = consume_qname!(t, start)
    return Token(TK_START, start, p, a, 1:0)
end

# '</' Name S? '>'
function parse_close!(t::Tokenizer)::Token
    start = t.pos
    t.pos += 2
    p, a = consume_qname!(t, start)
    skip_spaces!(t)
    consume_byte!(t, UInt8('>'), start, "invalid element")
    return Token(TK_CLOSE, start, p, a, 1:0)
end

# S Name Eq AttValue, or the end of the start tag.
function parse_attribute!(t::Tokenizer)::Token
    start = t.pos
    bad = "invalid attribute"
    has_space = starts_with_space(t)
    skip_spaces!(t)
    if t.pos <= t.n
        c = t.b[t.pos]
        if c == UInt8('/')
            at = t.pos
            t.pos += 1
            consume_byte!(t, UInt8('>'), start, bad)
            return Token(TK_EMPTY_END, at)
        elseif c == UInt8('>')
            t.pos += 1
            return Token(TK_OPEN_END, t.pos - 1)
        end
    end
    has_space || throw(xml_error(t, at_end(t) ? t.n + 1 : start, bad))
    astart = t.pos
    p, a = consume_qname!(t, start)
    consume_eq!(t, start, bad)
    q = consume_quote!(t, start, bad)
    # The attribute value must not contain the < character.
    v = consume_chars!(t, start, bad) do pos, c
        c != q && c != UInt32('<')
    end
    consume_byte!(t, q, start, bad)
    return Token(TK_ATTR, astart, p, a, v)
end

function parse_text!(t::Tokenizer)::Token
    start = t.pos
    bad = "invalid character data"
    text = consume_chars!(t, start, bad) do pos, c
        c != UInt32('<')
    end
    # `]]>` must not appear in text (https://www.w3.org/TR/xml/#syntax).
    s = view(t.b, text)
    for i in 1:(length(s)-2)
        s[i] == UInt8(']') && s[i+1] == UInt8(']') && s[i+2] == UInt8('>') &&
            throw(xml_error(t, start, bad))
    end
    return Token(TK_TEXT, start, 1:0, text, 1:0)
end

unknown(t::Tokenizer) = xml_error(t, t.pos, "unknown token")

# Markup allowed outside the root element: comments and processing instructions
# (but not a second XML declaration).
function prolog_markup!(t::Tokenizer)::Union{Nothing,Token}
    starts_with(t, "<!--") && return parse_comment!(t)
    if starts_with(t, "<?")
        starts_with(t, "<?xml ") && throw(unknown(t))
        return parse_pi!(t)
    end
    return nothing
end

"""
The next token, or `nothing` at the end of the text.
"""
function next_token!(t::Tokenizer)::Union{Nothing,Token}
    while t.pos <= t.n
        st = t.state
        if st == S_DECLARATION
            t.state = S_AFTER_DECLARATION
            starts_with(t, "<?xml ") && return parse_declaration!(t)
        elseif st == S_AFTER_DECLARATION
            if starts_with(t, "<!DOCTYPE")
                throw(syntax_error(:xml, t.pos - 1, "a DTD is not allowed in SenML XML"))
            end
            x = prolog_markup!(t)
            x === nothing || return x
            if starts_with_space(t)
                skip_spaces!(t)
            else
                t.state = S_AFTER_DTD
            end
        elseif st == S_AFTER_DTD
            x = prolog_markup!(t)
            x === nothing || return x
            if starts_with(t, "<!")
                throw(unknown(t))
            elseif cur(t) == UInt8('<')
                t.state = S_ATTRIBUTES
                return parse_element_start!(t)
            elseif starts_with_space(t)
                skip_spaces!(t)
            else
                throw(unknown(t))
            end
        elseif st == S_ELEMENTS
            if cur(t) == UInt8('<')
                t.pos + 1 > t.n && throw(unknown(t))
                nb = t.b[t.pos+1]
                if nb == UInt8('!')
                    starts_with(t, "<!--") && return parse_comment!(t)
                    starts_with(t, "<![CDATA[") && return parse_cdata!(t)
                    throw(unknown(t))
                elseif nb == UInt8('?')
                    starts_with(t, "<?xml ") && throw(unknown(t))
                    return parse_pi!(t)
                elseif nb == UInt8('/')
                    t.depth > 0 && (t.depth -= 1)
                    t.state = t.depth == 0 ? S_AFTER_ELEMENTS : S_ELEMENTS
                    return parse_close!(t)
                else
                    t.state = S_ATTRIBUTES
                    return parse_element_start!(t)
                end
            end
            return parse_text!(t)
        elseif st == S_ATTRIBUTES
            tok = parse_attribute!(t)
            if tok.kind == TK_OPEN_END || tok.kind == TK_EMPTY_END
                tok.kind == TK_OPEN_END && (t.depth += 1)
                t.state = t.depth == 0 ? S_AFTER_ELEMENTS : S_ELEMENTS
            end
            return tok
        else # S_AFTER_ELEMENTS
            x = prolog_markup!(t)
            x === nothing || return x
            starts_with_space(t) || throw(unknown(t))
            skip_spaces!(t)
        end
    end
    return nothing
end

#------------------------------------------------------------------- the reader

# Where the reader is in the document: before the root (PROLOG), inside `sensml`
# (RECORDS), after `</sensml>` (EPILOG).
const R_PROLOG = 0
const R_RECORDS = 1
const R_EPILOG = 2

"""
    RecordReader(input)

Reads the records of a SenML XML document (bytes or a string) one at a time. Throws
a `SenMLError` if the input is not UTF-8. Call [`next_record!`](@ref) until it
returns `nothing`, then [`finish`](@ref); or iterate it.

Records have no child elements, so namespaces only need two levels: the root's
declarations (kept here) and each `senml` element's own.
"""
mutable struct RecordReader
    t::Tokenizer
    state::Int
    index::Int
    root_default::Union{Nothing,String}
    root_prefixes::Vector{Pair{String,String}}
    root_prefix::String
end

# The byte offset of the first byte that is not part of valid UTF-8, or -1.
function first_invalid_utf8(s::String)::Int
    isvalid(s) && return -1
    i = 1
    while i <= ncodeunits(s)
        c = s[i]
        isvalid(c) || return i - 1
        i = nextind(s, i)
    end
    return ncodeunits(s)
end

function RecordReader(input::Union{AbstractString,AbstractVector{UInt8}})
    s = input isa String ? input : String(copy(input isa AbstractString ? codeunits(input) : input))
    bad = first_invalid_utf8(s)
    bad >= 0 && throw(syntax_error(:xml, bad, "SenML XML must be UTF-8"))
    return RecordReader(Tokenizer(s), R_PROLOG, 0, nothing, Pair{String,String}[], "")
end

str(r::RecordReader, range::UnitRange{Int}) = String(r.t.b[range])
is_whitespace(r::RecordReader, range::UnitRange{Int}) = all(is_space, view(r.t.b, range))
xerr(offset::Int, reason::String) = syntax_error(:xml, offset - 1, reason)
structure(reason::String) = SenMLError(:Structure; format = :xml, reason)

function whitespace_only(r::RecordReader, tok::Token)
    is_whitespace(r, tok.a) || throw(xerr(tok.start, "text is not allowed here"))
end

# A start tag with its attributes, collected before namespaces are resolved (an
# `xmlns` attribute may come after the attributes it applies to).
struct StartTag
    prefix::String
    local_::String
    offset::Int
    attributes::Vector{Tuple{String,String,UnitRange{Int},Int}}  # prefix, local, raw value, value start
    empty::Bool
end

function start_tag(r::RecordReader, tok::Token)::StartTag
    attributes = Tuple{String,String,UnitRange{Int},Int}[]
    while true
        x = next_token!(r.t)
        x === nothing && throw(incomplete(:xml))
        if x.kind == TK_ATTR
            push!(attributes, (str(r, x.p), str(r, x.a), x.v, first(x.v)))
        elseif x.kind == TK_OPEN_END || x.kind == TK_EMPTY_END
            return StartTag(str(r, tok.p), str(r, tok.a), tok.start, attributes, x.kind == TK_EMPTY_END)
        else
            throw(xerr(x.start, "malformed start tag"))
        end
    end
end

# The namespace URI of `prefix`. The element's own declarations come first, then
# the root's. The `xml` prefix is always bound to its fixed URI.
function namespace(r::RecordReader, tag::StartTag, prefix::String)::Union{Nothing,String}
    for (p, l, v, _) in tag.attributes
        declares = isempty(prefix) ? (isempty(p) && l == "xmlns") : (p == "xmlns" && l == prefix)
        declares && return str(r, v)
    end
    isempty(prefix) && return r.root_default
    prefix == "xml" && return XML_PREFIX_NAMESPACE
    for (p, uri) in r.root_prefixes
        p == prefix && return uri
    end
    return nothing
end

function root!(r::RecordReader, tag::StartTag)
    if tag.local_ != "sensml" || namespace(r, tag, tag.prefix) != XML_NAMESPACE
        throw(structure("the root element must be sensml in urn:ietf:params:xml:ns:senml"))
    end
    for (p, l, v, _) in tag.attributes
        if isempty(p) && l == "xmlns"
            r.root_default = str(r, v)
        elseif p == "xmlns"
            push!(r.root_prefixes, l => str(r, v))
        end
    end
    r.root_prefix = tag.prefix
    # `<sensml/>`: a document with no records (validation reports that).
    r.state = tag.empty ? R_EPILOG : R_RECORDS
    return nothing
end

function end_tag(r::RecordReader, tok::Token, prefix::String, local_::String)
    (tok.kind == TK_CLOSE && str(r, tok.p) == prefix && str(r, tok.a) == local_) ||
        throw(xerr(tok.start, "end tag does not match its start tag"))
end

function record!(r::RecordReader, tag::StartTag)::Record
    if tag.local_ != "senml" || namespace(r, tag, tag.prefix) != XML_NAMESPACE
        throw(xerr(tag.offset, "only senml elements may appear inside sensml"))
    end
    r.index += 1
    index = r.index
    b = RecordBuilder(index)
    for (prefix, label, raw, vstart) in tag.attributes
        # Skip namespace declarations and attributes with a prefix. In XML, an
        # attribute without a prefix is in no namespace, which is where the SenML
        # labels are.
        (!isempty(prefix) || label == "xmlns") && continue
        text = attribute_value(r, raw, vstart)
        l = label_from_text(label)
        if l != 0
            set!(b, l, typed(l, text, index))
        else
            extension!(b, label, text)
        end
    end
    if !tag.empty
        # The content must be empty (whitespace, comments and processing
        # instructions are allowed).
        while true
            x = next_token!(r.t)
            x === nothing && throw(incomplete(:xml))
            if x.kind == TK_COMMENT || x.kind == TK_PI
            elseif x.kind == TK_TEXT
                whitespace_only(r, x)
            elseif x.kind == TK_CLOSE
                end_tag(r, x, tag.prefix, "senml")
                break
            else
                throw(xerr(x.start, "a senml element has no content"))
            end
        end
    end
    return build(b)
end

"""
    next_record!(reader) -> Union{Record,Nothing}

The next record, or `nothing` at `</sensml>`.
"""
function next_record!(r::RecordReader)::Union{Nothing,Record}
    while true
        tok = next_token!(r.t)
        if tok === nothing
            r.state == R_PROLOG && throw(structure("no sensml element"))
            r.state == R_RECORDS && throw(incomplete(:xml))
            return nothing
        end
        k = tok.kind
        if k == TK_COMMENT || k == TK_PI
        elseif k == TK_DECL
            r.state == R_PROLOG || throw(xerr(tok.start, "unexpected markup"))
            if !isempty(tok.a)
                enc = codeunits(str(r, tok.a))
                (length(enc) == 5 && all(i -> SenML.ascii_lower(enc[i]) == codeunits("utf-8")[i], 1:5)) ||
                    throw(xerr(first(tok.a), "SenML XML must be UTF-8"))
            end
        elseif k == TK_TEXT
            whitespace_only(r, tok)
        elseif k == TK_CDATA
            is_whitespace(r, tok.a) || throw(xerr(tok.start, "text is not allowed here"))
        elseif k == TK_START && r.state == R_PROLOG
            root!(r, start_tag(r, tok))
            r.state == R_EPILOG && return nothing
        elseif k == TK_START && r.state == R_RECORDS
            return record!(r, start_tag(r, tok))
        elseif k == TK_CLOSE && r.state == R_RECORDS
            end_tag(r, tok, r.root_prefix, "sensml")
            r.state = R_EPILOG
            return nothing
        elseif k == TK_START
            throw(xerr(tok.start, "only one sensml element is allowed"))
        else
            throw(xerr(tok.start, "unexpected markup"))
        end
    end
end

"""
    finish(reader)

Checks that only comments, processing instructions and whitespace follow the root
element.
"""
function finish(r::RecordReader)
    r.state == R_EPILOG || throw(incomplete(:xml))
    while true
        tok = next_token!(r.t)
        tok === nothing && return nothing
        if tok.kind == TK_COMMENT || tok.kind == TK_PI
        elseif tok.kind == TK_TEXT
            whitespace_only(r, tok)
        else
            throw(xerr(tok.start, "data after the sensml element"))
        end
    end
end

Base.IteratorSize(::Type{RecordReader}) = Base.SizeUnknown()
Base.eltype(::Type{RecordReader}) = Record
function Base.iterate(r::RecordReader, _ = nothing)
    x = next_record!(r)
    return x === nothing ? nothing : (x, nothing)
end

# An unsigned number in base 10 or 16 as Rust's `u32` parser reads it: an
# optional `+`, then at least one digit; `nothing` when it is not that or too big.
function parse_u32(s::AbstractString, base::Int)::Union{Nothing,UInt32}
    b = codeunits(s)
    i = 1
    i <= length(b) && b[i] == UInt8('+') && (i += 1)
    i > length(b) && return nothing
    x = UInt64(0)
    while i <= length(b)
        c = b[i]
        d = UInt8('0') <= c <= UInt8('9') ? c - UInt8('0') :
            base == 16 && UInt8('a') <= c <= UInt8('f') ? c - UInt8('a') + 10 :
            base == 16 && UInt8('A') <= c <= UInt8('F') ? c - UInt8('A') + 10 : return nothing
        x = x * base + d
        x > typemax(UInt32) && return nothing
        i += 1
    end
    return UInt32(x)
end

# A predefined entity or a character reference (`lt`, `#38`, `#x26`); `name` is the
# text between `&` and `;`.
function reference(name::AbstractString)::Union{Nothing,Char}
    name == "lt" && return '<'
    name == "gt" && return '>'
    name == "amp" && return '&'
    name == "quot" && return '"'
    name == "apos" && return '\''
    code = startswith(name, "#x") ? parse_u32(SubString(name, 3), 16) :
        startswith(name, "#") ? parse_u32(SubString(name, 2), 10) : nothing
    code === nothing && return nothing
    (code > 0x10ffff || 0xd800 <= code <= 0xdfff) && return nothing
    # XML 1.0 Char (https://www.w3.org/TR/xml/#NT-Char).
    is_xml_char(code) || return nothing
    return Char(code)
end

# The normalized value of an attribute (XML 1.0 section 3.3.3): references
# expanded, and each literal tab, newline and carriage return (or CR LF pair)
# replaced by a space. A tab or newline written as a character reference stays.
# https://www.w3.org/TR/xml/#AVNormalize
function attribute_value(r::RecordReader, raw::UnitRange{Int}, vstart::Int)::String
    b = r.t.b
    any(i -> b[i] in (UInt8('&'), 0x09, 0x0a, 0x0d), raw) || return str(r, raw)
    out = IOBuffer()
    i = first(raw)
    stop = last(raw)
    while i <= stop
        c = b[i]
        if c == UInt8('&')
            j = findnext(==(UInt8(';')), b, i)
            (j === nothing || j > stop) && throw(xerr(vstart, "unterminated reference"))
            ch = reference(String(b[(i+1):(j-1)]))
            ch === nothing && throw(xerr(vstart, "unknown or invalid reference"))
            print(out, ch)
            i = j + 1
        elseif c == 0x0d
            write(out, UInt8(' '))
            i += (i + 1 <= stop && b[i+1] == 0x0a) ? 2 : 1
        elseif c == 0x09 || c == 0x0a
            write(out, UInt8(' '))
            i += 1
        else
            write(out, c)
            i += 1
        end
    end
    return String(take!(out))
end

# XSD whiteSpace="collapse" for a single token: leading and trailing spaces are
# removed (normalization has already turned tabs and newlines into spaces).
collapse(s::String) = strip(==(' '), s)

# An `xs:double` value in its text form (https://www.w3.org/TR/xmlschema-2/#double),
# checked against (\+|-)?([0-9]+(\.[0-9]*)?|\.[0-9]+)([Ee](\+|-)?[0-9]+)?
# The special values (INF, -INF, NaN) are not SenML numbers.
function xs_double(t::AbstractString, l::Int, index::Int)::Float64
    t in ("INF", "+INF", "-INF", "NaN") && throw(record_error(:NonFinite, index, label_text(l)))
    b = codeunits(t)
    n = length(b)
    isdig(i) = i <= n && UInt8('0') <= b[i] <= UInt8('9')
    i = 1
    i <= n && (b[i] == UInt8('+') || b[i] == UInt8('-')) && (i += 1)
    s = i
    while isdig(i)
        i += 1
    end
    digits = i - s
    if i <= n && b[i] == UInt8('.')
        i += 1
        s = i
        while isdig(i)
            i += 1
        end
        digits += i - s
    end
    if digits > 0 && i <= n && (b[i] == UInt8('e') || b[i] == UInt8('E'))
        i += 1
        i <= n && (b[i] == UInt8('+') || b[i] == UInt8('-')) && (i += 1)
        s = i
        while isdig(i)
            i += 1
        end
        i == s && (digits = 0)
    end
    (digits == 0 || i != n + 1) && throw(record_error(:WrongType, index, label_text(l)))
    v = parse_number(t)
    isfinite(v) || throw(record_error(:NonFinite, index, label_text(l)))
    return v
end

# The value of a registered label, by its XML type (Table 5 in section 7).
function typed(l::Int, text::String, index::Int)
    wrong() = record_error(:WrongType, index, label_text(l))
    t = label_type(l)
    if t == T_STRING
        return text
    elseif t == T_NUMBER
        return xs_double(collapse(text), l, index)
    elseif t == T_VERSION
        c = collapse(text)
        digits = startswith(c, '+') ? SubString(c, 2) : c
        if isempty(digits) || !all(x -> UInt8('0') <= x <= UInt8('9'), codeunits(digits))
            # `bver` is an `xs:int`. A well-formed negative number is a bad version;
            # anything else that is not digits is the wrong type.
            neg = startswith(c, '-') && ncodeunits(c) > 1 &&
                all(x -> UInt8('0') <= x <= UInt8('9'), codeunits(SubString(c, 2)))
            throw(neg ? record_error(:InvalidVersion, index) : wrong())
        end
        # xs:int: at most 2147483647 (https://www.w3.org/TR/xmlschema-2/#int).
        v = tryparse(UInt64, digits)
        (v === nothing || v > 2_147_483_647) && throw(wrong())
        return v
    elseif t == T_BOOL
        # xs:boolean allows "true", "false", "1" and "0".
        c = collapse(text)
        (c == "true" || c == "1") && return true
        (c == "false" || c == "0") && return false
        throw(wrong())
    else # T_DATA
        d = base64url_decode(text)
        d === nothing && throw(record_error(:InvalidBase64, index))
        return d
    end
end

"""
    decode_unchecked(input) -> Pack

Reads a SenML XML document (bytes or a string), checking only the XML form (not
the rules of section 4).
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

Reads a SenML XML document (bytes or a string) and validates the pack. Throws a
`SenMLError`.
"""
function decode(input)::Pack
    p = decode_unchecked(input)
    validate(p)
    return p
end

#----------------------------------------------------------------------- writing
#
# Attribute values escape `&`, `<` and `"`. They also escape tab, newline and
# carriage return, so that these survive attribute-value normalization, which
# would turn them into spaces.

unrepresentable(reason::String) = SenMLError(:Unrepresentable; format = :xml, reason)

# An XML NCName (a name with no colon): what the decoder accepts as an attribute
# name, so a pack it read can always be written back.
function is_ncname(s::String)
    isempty(s) && return false
    for (i, ch) in enumerate(s)
        isvalid(ch) || return false
        c = UInt32(ch)
        c == UInt32(':') && return false
        (i == 1 ? is_name_start(c) : is_name_char(c)) || return false
    end
    return true
end

function write_attribute(io::IO, label::String, value::String)
    write(io, UInt8(' '), label, "=\"")
    for ch in value
        isvalid(ch) || throw(unrepresentable("text that is not UTF-8"))
        c = UInt32(ch)
        if ch == '&'
            write(io, "&amp;")
        elseif ch == '<'
            write(io, "&lt;")
        elseif ch == '"'
            write(io, "&quot;")
        elseif ch == '\t'
            write(io, "&#9;")
        elseif ch == '\n'
            write(io, "&#10;")
        elseif ch == '\r'
            write(io, "&#13;")
        elseif c < 0x20 || c == 0xfffe || c == 0xffff
            # Other control characters, U+FFFE and U+FFFF are not XML 1.0
            # characters, not even as references.
            throw(unrepresentable("a character XML 1.0 does not allow"))
        else
            print(io, ch)
        end
    end
    write(io, UInt8('"'))
    return nothing
end

function write_number_attribute(io::IO, label::AbstractString, v::Float64, index::Int)
    isfinite(v) || throw(record_error(:NonFinite, index, label))
    write(io, UInt8(' '), label, "=\"")
    write_number(io, v)
    write(io, UInt8('"'))
    return nothing
end

# A string or number attribute, when present.
write_field(::IO, ::String, ::Nothing, ::Int) = nothing
write_field(io::IO, label::String, x::String, ::Int) = write_attribute(io, label, x)
write_field(io::IO, label::String, x::Float64, index::Int) = write_number_attribute(io, label, x, index)

function write_value(io::IO, label::AbstractString, v::Value, index::Int)
    if v isa Float64
        write_number_attribute(io, label, v, index)
    elseif v isa String
        write_attribute(io, label, v)
    elseif v isa Bool
        write_attribute(io, label, v ? "true" : "false")
    else
        # base64url needs no escaping.
        out = Vector{UInt8}(undef, base64url_length(length(v)))
        write_base64url!(out, 1, v)
        write(io, UInt8(' '), label, "=\"", out, UInt8('"'))
    end
    return nothing
end

"""
    encode_record(io, record, index)

Writes one `<senml .../>` element (for writing a document one piece at a time; see
[`StreamEncoder`](@ref)). `index` (1-based) is only used in error reports.
"""
function encode_record(io::IO, r::Record, index::Integer = 1)
    index = Int(index)
    write(io, "<senml")
    # One call per field, not a loop over a tuple: the fields have different
    # types, and a loop over them would box each one.
    write_field(io, "bn", r.bn, index)
    write_field(io, "bt", r.bt, index)
    write_field(io, "bu", r.bu, index)
    write_field(io, "bv", r.bv, index)
    write_field(io, "bs", r.bs, index)
    if r.bver !== nothing
        # `bver` is an xs:int (https://www.w3.org/TR/xmlschema-2/#int).
        r.bver > 2_147_483_647 && throw(unrepresentable("bver above the xs:int range"))
        write(io, " bver=\"")
        print(io, r.bver)
        write(io, UInt8('"'))
    end
    write_field(io, "n", r.n, index)
    write_field(io, "u", r.u, index)
    write_field(io, "t", r.t, index)
    write_field(io, "ut", r.ut, index)
    write_field(io, "s", r.s, index)
    v = r.value
    v === nothing || write_value(io, label_text(value_label(v)), v, index)
    for e in r.extensions
        is_ncname(e.label) || throw(unrepresentable("an extension label that is not an XML name"))
        write_value(io, e.label, e.value, index)
    end
    write(io, "/>")
    return nothing
end

const START_TAG = "<sensml xmlns=\"" * XML_NAMESPACE * "\">"

"""
    encode_unchecked(pack) -> Vector{UInt8}

Writes a pack as it is, without validating (values XML cannot carry are still
refused).
"""
function encode_unchecked(p::AbstractVector{Record})::Vector{UInt8}
    io = IOBuffer()
    write(io, START_TAG)
    for (i, r) in enumerate(p)
        encode_record(io, r, i)
    end
    write(io, "</sensml>")
    return take!(io)
end

"""
    encode(pack) -> Vector{UInt8}

Validates a pack and writes it as SenML XML.
"""
function encode(p::AbstractVector{Record})::Vector{UInt8}
    validate(p)
    return encode_unchecked(p)
end

"""
    StreamEncoder()

Writes a SenSML XML document one piece at a time: the `sensml` start tag before
the first record ([`record!`](@ref)), one `senml` element per record, and the end
tag ([`finish!`](@ref)). It does not validate.
"""
mutable struct StreamEncoder
    records::Int
end

StreamEncoder() = StreamEncoder(0)

"""
    record!(enc, io, record)

Writes the next record (with the `sensml` start tag before the first).
"""
function record!(s::StreamEncoder, io::IO, r::Record)
    s.records == 0 && write(io, START_TAG)
    s.records += 1
    encode_record(io, r, s.records)
    return nothing
end

"""
    finish!(enc, io)

Writes the end tag (and the start tag if no record was written).
"""
function finish!(s::StreamEncoder, io::IO)
    s.records == 0 && write(io, START_TAG)
    write(io, "</sensml>")
    return nothing
end

end # module Xml
