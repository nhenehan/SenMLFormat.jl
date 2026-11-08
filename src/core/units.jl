# The SenML Units registry as RFC 8428 created it (Table 6).
# https://www.rfc-editor.org/rfc/rfc8428#section-12.1
#
# Later additions are not included: the new units of RFC 8798 section 2 and its
# secondary units (section 3). Unit symbols are case-sensitive.

"""
    Unit(symbol, description, deprecated)

One registered unit: the symbol used in `u` / `bu` (for example `Cel`), what it
measures as Table 6 describes it, and whether Table 6 marks it `*` (new
implementations are NOT RECOMMENDED to write it, but readers SHOULD understand it).
"""
struct Unit
    symbol::String
    description::String
    deprecated::Bool
end

"RFC 8428 Table 6, in table order."
const UNITS = (
    Unit("m", "meter", false),
    Unit("kg", "kilogram", false),
    Unit("g", "gram", true),
    Unit("s", "second", false),
    Unit("A", "ampere", false),
    Unit("K", "kelvin", false),
    Unit("cd", "candela", false),
    Unit("mol", "mole", false),
    Unit("Hz", "hertz", false),
    Unit("rad", "radian", false),
    Unit("sr", "steradian", false),
    Unit("N", "newton", false),
    Unit("Pa", "pascal", false),
    Unit("J", "joule", false),
    Unit("W", "watt", false),
    Unit("C", "coulomb", false),
    Unit("V", "volt", false),
    Unit("F", "farad", false),
    Unit("Ohm", "ohm", false),
    Unit("S", "siemens", false),
    Unit("Wb", "weber", false),
    Unit("T", "tesla", false),
    Unit("H", "henry", false),
    Unit("Cel", "degrees Celsius", false),
    Unit("lm", "lumen", false),
    Unit("lx", "lux", false),
    Unit("Bq", "becquerel", false),
    Unit("Gy", "gray", false),
    Unit("Sv", "sievert", false),
    Unit("kat", "katal", false),
    Unit("m2", "square meter (area)", false),
    Unit("m3", "cubic meter (volume)", false),
    Unit("l", "liter (volume)", true),
    Unit("m/s", "meter per second (velocity)", false),
    Unit("m/s2", "meter per square second (acceleration)", false),
    Unit("m3/s", "cubic meter per second (flow rate)", false),
    Unit("l/s", "liter per second (flow rate)", true),
    Unit("W/m2", "watt per square meter (irradiance)", false),
    Unit("cd/m2", "candela per square meter (luminance)", false),
    Unit("bit", "bit (information content)", false),
    Unit("bit/s", "bit per second (data rate)", false),
    Unit("lat", "degrees latitude", false),
    Unit("lon", "degrees longitude", false),
    Unit("pH", "pH value (acidity; logarithmic quantity)", false),
    Unit("dB", "decibel (logarithmic quantity)", false),
    Unit("dBW", "decibel relative to 1 W (power level)", false),
    Unit("Bspl", "bel (sound pressure level; logarithmic quantity)", true),
    Unit("count", "1 (counter value)", false),
    Unit("/", "1 (ratio, e.g., value of a switch)", false),
    Unit("%", "1 (ratio, e.g., value of a switch)", true),
    Unit("%RH", "percentage (relative humidity)", false),
    Unit("%EL", "percentage (remaining battery energy level)", false),
    Unit("EL", "seconds (remaining battery energy level)", false),
    Unit("1/s", "1 per second (event rate)", false),
    Unit("1/min", "1 per minute (event rate, \"rpm\")", true),
    Unit("beat/min", "1 per minute (heart rate in beats per minute)", true),
    Unit("beats", "1 (cumulative number of heart beats)", true),
    Unit("S/m", "siemens per meter (conductivity)", false),
)

"""
    lookup_unit(symbol) -> Union{Unit,Nothing}

The registered unit with this symbol (case-sensitive).
"""
function lookup_unit(symbol::AbstractString)::Union{Nothing,Unit}
    for u in UNITS
        u.symbol == symbol && return u
    end
    return nothing
end
