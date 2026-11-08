# Number conversions shared by the codecs.
#
# SenML numbers are IEEE 754 doubles (RFC 8428 section 5). The text formats (JSON,
# XML) use the shortest digits that read back as the same double. Very large or
# very small numbers get an exponent with a lower-case `e` (section 5 asks for
# lower case). CBOR uses the most compact exact form: an integer when the value is
# a whole number, otherwise the smallest float size that holds it exactly
# (section 6). EXI uses a decimal mantissa and exponent (EXI 7.1.4).
# https://www.rfc-editor.org/rfc/rfc8428#section-5
# https://www.rfc-editor.org/rfc/rfc8428#section-6
# https://www.w3.org/TR/exi/#encodingFloat
#
# The shortest digits come from Julia's Ryu (`Base.Ryu.reduce_shortest`), which
# gives the same digits as Rust's shortest float printing that rsenml uses.

"""
    decimal_parts(v) -> (mantissa::Int64, exponent::Int)

The shortest decimal `(mantissa, exponent)` with `mantissa * 10^exponent == v`
after rounding to the nearest double, with no trailing zeros in the mantissa:
`20.0` is `(2, 1)`, `120.1` is `(1201, -1)`, `0.0` is `(0, 0)`. `v` must be finite.
This is the EXI Float form of the shortest text.
"""
function decimal_parts(v::Float64)::Tuple{Int64,Int}
    v == 0 && return (Int64(0), 0)
    m, e = shortest(abs(v))
    mi = Int64(m)
    return (v < 0 ? -mi : mi, e)
end

"""
    shortest(a) -> (m::UInt64, e::Int)

The shortest digits of `a > 0` as Rust prints them: `a` reads back from
`m * 10^e`, and `m` has no trailing zeros.

Ryu and Rust agree except on exact ties: when `a` is exactly halfway between two
shortest candidates, Ryu picks the even one and Rust picks the upper one (Rust's
Dragon4 rounds up when the rest is exactly one half). So when Ryu's answer `m` is
exactly half a unit below `a`, and `m + 1` reads back too, use `m + 1`.
"""
function shortest(a::Float64)::Tuple{UInt64,Int}
    m, e = Base.Ryu.reduce_shortest(a)
    e = Int(e)
    if exactly_half_above(a, m, e) && decimal_to_float(m + 1, e) === a
        m += 1
        while m % 10 == 0
            m ÷= 10
            e += 1
        end
    end
    return (m, e)
end

# Whether a == (m + 1/2) * 10^e exactly, that is 2 * a == (2m + 1) * 10^e. With
# a = M * 2^E (M an integer), the powers of two on both sides must match first:
# 2m + 1 is odd and 10^e holds 2^e. That cheap test rules out almost every value;
# the rest are compared exactly with big integers.
function exactly_half_above(a::Float64, m::UInt64, e::Int)::Bool
    bits = reinterpret(UInt64, a)
    ex = Int((bits >> 52) & 0x7ff)
    M = ex == 0 ? bits & 0x000f_ffff_ffff_ffff : (bits & 0x000f_ffff_ffff_ffff) | 0x0010_0000_0000_0000
    E = ex == 0 ? -1074 : ex - 1075
    trailing_zeros(M) + E + 1 == e || return false
    lhs = big(M)
    rhs = 2 * big(m) + 1
    E + 1 >= 0 ? (lhs <<= (E + 1)) : (rhs <<= -(E + 1))
    e >= 0 ? (rhs *= big(10)^e) : (lhs *= big(10)^(-e))
    return lhs == rhs
end

"""
    format_number(v) -> String

The shortest text that reads back as `v`: a valid JSON number and a valid
`xs:double`. Magnitudes from 1e-5 up to (not including) 1e16 are written without
an exponent (`23.1`, `20`, `1276020076.001`, `0.00001`); others with a lower-case
`e` and no `+` (`1e16`, `1.5e-7`, `1.7976931348623157e308`). `-0.0` is `-0`. This
is how rsenml (Rust's `{}` and `{:e}`) writes numbers. `v` must be finite.
"""
function format_number(v::Float64)
    io = IOBuffer(; sizehint = 24)
    write_number(io, v)
    return String(take!(io))
end

function write_number(io::IO, v::Float64)
    if v == 0
        write(io, signbit(v) ? "-0" : "0")
        return nothing
    end
    m, e = shortest(abs(v))
    digits = string(m)
    k = ncodeunits(digits)
    v < 0 && write(io, UInt8('-'))
    a = abs(v)
    if 1e-5 <= a < 1e16
        if e >= 0
            # Whole number: the digits, then e zeros.
            write(io, digits)
            for _ in 1:e
                write(io, UInt8('0'))
            end
        else
            point = k + e  # digits before the point
            if point > 0
                write(io, SubString(digits, 1, point), UInt8('.'), SubString(digits, point + 1))
            else
                write(io, "0.")
                for _ in 1:(-point)
                    write(io, UInt8('0'))
                end
                write(io, digits)
            end
        end
    else
        # d.ddde<n>: one digit before the point, n = e + k - 1.
        write(io, codeunit(digits, 1))
        k > 1 && write(io, UInt8('.'), SubString(digits, 2))
        write(io, UInt8('e'))
        print(io, e + k - 1)
    end
    return nothing
end

"""
    as_exact_int(v) -> Union{Int64,Nothing}

`v` as an `Int64` when it is a whole number that an `Int64` holds exactly. `-0.0`
does not count, because an integer would lose its sign.
"""
function as_exact_int(v::Float64)::Union{Nothing,Int64}
    -9.223372036854775808e18 <= v < 9.223372036854775808e18 || return nothing
    v == trunc(v) || return nothing
    (v == 0 && signbit(v)) && return nothing
    return unsafe_trunc(Int64, v)
end

"""
    to_float16_exact(v) -> Union{Float16,Nothing}

`v` as a half-precision float when the conversion is exact (`-0.0` included). CBOR
uses this for its smallest float size
([RFC 8949 section 3.3](https://www.rfc-editor.org/rfc/rfc8949#section-3.3)).
"""
function to_float16_exact(v::Float64)::Union{Nothing,Float16}
    isfinite(v) || return nothing
    h = Float16(v)
    return reinterpret(UInt64, Float64(h)) == reinterpret(UInt64, v) ? h : nothing
end

"`v` as a `Float32` when the conversion is exact."
function to_float32_exact(v::Float64)::Union{Nothing,Float32}
    isfinite(v) || return nothing
    f = Float32(v)
    return reinterpret(UInt64, Float64(f)) == reinterpret(UInt64, v) ? f : nothing
end

"""
    parse_number(text) -> Float64

A decimal number in JSON or `xs:double` text form (`-12.5e+3`, `+.5`, `7`), as the
nearest double (correctly rounded). The caller has already checked the syntax.
Numbers too big for a double become infinite, and numbers too small become zero,
with their sign.
"""
function parse_number(text::AbstractString)::Float64
    x = tryparse(Float64, text)
    x === nothing || return x
    # Julia's parser refuses a result that overflows to infinity or underflows to
    # zero. Which one it is depends on the decimal exponent of the leading digit.
    return out_of_range(codeunits(text))
end

function out_of_range(b::AbstractVector{UInt8})::Float64
    i = firstindex(b)
    negative = false
    if i <= lastindex(b) && (b[i] == UInt8('-') || b[i] == UInt8('+'))
        negative = b[i] == UInt8('-')
        i += 1
    end
    # lead: the power of ten of the first non-zero digit, before the exponent part.
    lead = 0
    seen_point = false
    found = false
    int_digits = 0
    while i <= lastindex(b)
        c = b[i]
        if c == UInt8('.')
            seen_point = true
        elseif UInt8('0') <= c <= UInt8('9')
            if !seen_point
                (found || c != UInt8('0')) && (int_digits += 1)
                c != UInt8('0') && (found = true)
            else
                if !found
                    lead -= 1
                    c != UInt8('0') && (found = true)
                end
            end
        else
            break
        end
        i += 1
    end
    lead = int_digits > 0 ? int_digits : lead
    exp = Int128(0)
    if i <= lastindex(b) && (b[i] == UInt8('e') || b[i] == UInt8('E'))
        i += 1
        eneg = false
        if i <= lastindex(b) && (b[i] == UInt8('-') || b[i] == UInt8('+'))
            eneg = b[i] == UInt8('-')
            i += 1
        end
        while i <= lastindex(b)
            exp = min(exp * 10 + (b[i] - UInt8('0')), Int128(10)^30)
            i += 1
        end
        eneg && (exp = -exp)
    end
    big = found && lead + exp > 0
    return negative ? (big ? -Inf : -0.0) : (big ? Inf : 0.0)
end

"""
    decimal_to_float(mantissa, exponent) -> Float64

The double nearest to `mantissa * 10^exponent` (correctly rounded). A zero
mantissa gives `+0.0`.
"""
decimal_to_float(mantissa::Integer, exponent::Integer) =
    mantissa == 0 ? 0.0 : parse_number(string(mantissa, 'e', exponent))
