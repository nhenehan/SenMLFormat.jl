# Base64 with the URL-safe alphabet and no padding, the text form of the Data
# Value in JSON and XML (RFC 8428 sections 5 and 7).
# https://www.rfc-editor.org/rfc/rfc4648#section-5
#
# Decoding is strict. It refuses padding, characters outside the alphabet, and
# non-zero bits after the last octet (RFC 4648 section 3.5 allows this).

const B64_ALPHABET = codeunits("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")

"Length of the encoding of `n` octets."
base64url_length(n::Integer) = n ÷ 3 * 4 + (0, 2, 3)[n % 3 + 1]

"""
    base64url_encode(data) -> String

`data` as base64url without padding.
"""
function base64url_encode(data::AbstractVector{UInt8})
    out = Vector{UInt8}(undef, base64url_length(length(data)))
    write_base64url!(out, 1, data)
    return String(out)
end

# Writes the encoding of `data` into `out` from position `at`; returns the next
# position. Each group of up to 3 octets is packed into a 24-bit number (missing
# octets are zero) and written as 6-bit groups, high group first. A group of k
# octets needs k + 1 characters.
function write_base64url!(out::Vector{UInt8}, at::Int, data::AbstractVector{UInt8})
    i = firstindex(data)
    last = lastindex(data)
    while i <= last
        k = min(3, last - i + 1)
        x = UInt32(data[i]) << 16
        k > 1 && (x |= UInt32(data[i+1]) << 8)
        k > 2 && (x |= UInt32(data[i+2]))
        for j in 0:k
            out[at] = B64_ALPHABET[((x >> (18 - 6j)) & 0x3f) + 1]
            at += 1
        end
        i += 3
    end
    return at
end

function b64_sextet(c::UInt8)::Int
    UInt8('A') <= c <= UInt8('Z') && return Int(c - UInt8('A'))
    UInt8('a') <= c <= UInt8('z') && return Int(c - UInt8('a')) + 26
    UInt8('0') <= c <= UInt8('9') && return Int(c - UInt8('0')) + 52
    c == UInt8('-') && return 62
    c == UInt8('_') && return 63
    return -1
end

"""
    base64url_decode(text) -> Union{Vector{UInt8},Nothing}

Decodes base64url without padding. Returns `nothing` if `text` is not exactly that.
"""
base64url_decode(text::AbstractString) = base64url_decode(codeunits(text))

function base64url_decode(b::AbstractVector{UInt8})::Union{Nothing,Vector{UInt8}}
    len = length(b)
    # A last group of 1 character holds only 6 bits, less than one octet.
    len % 4 == 1 && return nothing
    out = UInt8[]
    sizehint!(out, len ÷ 4 * 3 + 2)
    i = firstindex(b)
    last = lastindex(b)
    while i <= last
        k = min(4, last - i + 1)
        x = UInt32(0)
        for j in 0:(k-1)
            s = b64_sextet(b[i+j])
            s < 0 && return nothing
            x = (x << 6) | UInt32(s)
        end
        if k == 4
            push!(out, (x >> 16) % UInt8, (x >> 8) % UInt8, x % UInt8)
        elseif k == 3
            # 18 bits: 2 octets plus 2 spare bits, which must be zero.
            x & 0x3 != 0 && return nothing
            push!(out, (x >> 10) % UInt8, (x >> 2) % UInt8)
        else
            # 12 bits: 1 octet plus 4 spare bits, which must be zero.
            x & 0xf != 0 && return nothing
            push!(out, (x >> 4) % UInt8)
        end
        i += 4
    end
    return out
end
