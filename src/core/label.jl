# The SenML labels of RFC 8428 Table 1, with their JSON/XML names and their CBOR
# integer keys (Table 4).
# https://www.rfc-editor.org/rfc/rfc8428#section-4.3
# https://www.rfc-editor.org/rfc/rfc8428#section-6
#
# A label is an Int from 1 to 15: its place in the order SenML.jl writes fields
# in. That is the order of the RFC's own examples (bn bt bu bv bs bver n u t ut s
# v vs vb vd), so the JSON of section 5.1.2 and the CBOR of section 6 come out
# byte for byte.

const L_BN = 1
const L_BT = 2
const L_BU = 3
const L_BV = 4
const L_BS = 5
const L_BVER = 6
const L_N = 7
const L_U = 8
const L_T = 9
const L_UT = 10
const L_S = 11
const L_V = 12
const L_VS = 13
const L_VB = 14
const L_VD = 15

"The label texts, in write order."
const LABEL_TEXT = ("bn", "bt", "bu", "bv", "bs", "bver", "n", "u", "t", "ut", "s", "v", "vs", "vb", "vd")

"The CBOR map keys of Table 4, in write order."
const LABEL_CBOR = (-2, -3, -4, -5, -6, -1, 0, 1, 6, 7, 5, 2, 3, 4, 8)

# Value types of Tables 2 and 5: text, number, version (positive integer), boolean,
# data (base64url text in JSON and XML, a byte string in CBOR).
const T_STRING = 1
const T_NUMBER = 2
const T_VERSION = 3
const T_BOOL = 4
const T_DATA = 5

const LABEL_TYPE = (
    T_STRING, T_NUMBER, T_STRING, T_NUMBER, T_NUMBER, T_VERSION, T_STRING, T_STRING,
    T_NUMBER, T_NUMBER, T_NUMBER, T_NUMBER, T_STRING, T_BOOL, T_DATA,
)

label_text(l::Int) = LABEL_TEXT[l]
label_type(l::Int) = LABEL_TYPE[l]
is_base_label(l::Int) = l <= L_BVER
is_value_label(l::Int) = l >= L_V

"""
    label_from_text(s) -> Int

The label with this JSON member / XML attribute name, or 0.
"""
function label_from_text(s::AbstractString)::Int
    n = ncodeunits(s)
    (n == 0 || n > 4) && return 0
    for l in 1:15
        LABEL_TEXT[l] == s && return l
    end
    return 0
end

"""
    label_from_cbor(key) -> Int

The label with this CBOR map key (Table 4), or 0.
"""
function label_from_cbor(key::Integer)::Int
    -6 <= key <= 8 || return 0
    for l in 1:15
        LABEL_CBOR[l] == key && return l
    end
    return 0
end

"""
    is_must_understand(label)

[Section 4.4](https://www.rfc-editor.org/rfc/rfc8428#section-4.4): a label that
ends in `_` must be understood. A reader that does not know such a label must fail.
"""
is_must_understand(label::AbstractString) = endswith(label, '_')

"""
    is_base_label_text(label)

[Section 12.2](https://www.rfc-editor.org/rfc/rfc8428#section-12.2): base labels
start with `b`, and regular labels must not.
"""
is_base_label_text(label::AbstractString) = startswith(label, 'b')
