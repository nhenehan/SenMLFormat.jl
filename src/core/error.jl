# The one error type every SenML.jl codec throws.

"""
    SenMLError <: Exception

Everything that can go wrong reading, checking, resolving or writing SenML. `kind`
names what went wrong; the names are those of rsenml's `Error` variants:

| `kind` | Meaning |
|---|---|
| `:Syntax` | the input is not well-formed JSON, CBOR, XML or EXI (`format`, `offset`, `reason`) |
| `:Incomplete` | the input ended inside the pack (`format`); for a SenSML stream: wait for more bytes |
| `:WrongType` | a registered label has a value of the wrong type (`record`, `label`) |
| `:DuplicateLabel` | a label occurs twice in one record (`record`, `label`) |
| `:MultipleValues` | more than one of `v`, `vs`, `vb`, `vd` (`record`) |
| `:MustUnderstand` | an unknown label ending in `_` (`record`, `label`) |
| `:InvalidLabel` | an extension uses the name of a registered label (`record`, `label`) |
| `:InvalidBase64` | `vd` is not unpadded base64url (`record`) |
| `:NonFinite` | a number is infinite or NaN (`record`, `label`) |
| `:EmptyPack` | a pack needs at least one record |
| `:MissingValue` | a record with regular fields but neither a value nor a sum (`record`) |
| `:MissingName` | a measurement with no name and no base name (`record`) |
| `:InvalidName` | base name + name breaks the rule of RFC 8428 section 4.5.1 (`record`) |
| `:InvalidVersion` | `bver` is not a positive integer (`record`) |
| `:UnsupportedVersion` | `bver` is newer than 10 (`record`, `version`) |
| `:InconsistentVersion` | records with different versions (`record`) |
| `:UnregisteredUnit` | a unit outside the registry, when registered units are required (`record`) |
| `:RelativeTime` | a relative time and no "now" to resolve it (`record`) |
| `:Structure` | the XML or EXI root or record element is wrong (`format`, `reason`) |
| `:SchemaId` | the EXI stream does not name schemaId "a" (`found`) |
| `:Unrepresentable` | the value cannot be written in this representation (`format`, `reason`) |
| `:Exi` | an EXI error with no SenML meaning (`reason`) |

`record` is the 1-based position of the record in the pack (0 when it does not
apply). `offset` is a 0-based byte offset into the input (-1 when it does not
apply); EXI works in bits, so it gives the byte that holds the bit. `format` is
`:json`, `:cbor`, `:xml`, `:exi`, or `:none`.
"""
struct SenMLError <: Exception
    kind::Symbol
    format::Symbol
    record::Int
    offset::Int
    label::String
    reason::String
    version::UInt64
    found::Union{Nothing,String}
end

function SenMLError(
    kind::Symbol;
    format::Symbol = :none,
    record::Integer = 0,
    offset::Integer = -1,
    label::AbstractString = "",
    reason::AbstractString = "",
    version::Integer = 0,
    found::Union{Nothing,AbstractString} = nothing,
)
    return SenMLError(
        kind,
        format,
        Int(record),
        Int(offset),
        String(label),
        String(reason),
        UInt64(version),
        found === nothing ? nothing : String(found),
    )
end

# Shorthands used by the readers and writers. They return the error; the caller
# throws it.
syntax_error(format::Symbol, offset::Integer, reason::AbstractString) =
    SenMLError(:Syntax; format, offset, reason)
incomplete(format::Symbol) = SenMLError(:Incomplete; format)
record_error(kind::Symbol, record::Integer) = SenMLError(kind; record)
record_error(kind::Symbol, record::Integer, label::AbstractString) =
    SenMLError(kind; record, label)

format_name(f::Symbol) = f === :json ? "JSON" : f === :cbor ? "CBOR" : f === :xml ? "XML" :
    f === :exi ? "EXI" : ""

function Base.showerror(io::IO, e::SenMLError)
    k = e.kind
    f = format_name(e.format)
    r = e.record
    print(io, "SenMLError: ")
    if k === :Syntax
        print(io, "invalid ", f, " at byte ", e.offset, ": ", e.reason)
    elseif k === :Incomplete
        print(io, f, " input ends inside the pack")
    elseif k === :WrongType
        print(io, "record ", r, ": wrong value type for label ", e.label)
    elseif k === :DuplicateLabel
        print(io, "record ", r, ": label ", e.label, " occurs twice")
    elseif k === :MultipleValues
        print(io, "record ", r, ": more than one of v, vs, vb, vd")
    elseif k === :MustUnderstand
        print(io, "record ", r, ": label ", e.label, " must be understood and is not supported")
    elseif k === :InvalidLabel
        print(io, "record ", r, ": label ", e.label, " is not valid here")
    elseif k === :InvalidBase64
        print(io, "record ", r, ": vd is not unpadded base64url")
    elseif k === :NonFinite
        print(io, "record ", r, ": ", e.label, " is not a finite number")
    elseif k === :EmptyPack
        print(io, "a SenML pack needs at least one record")
    elseif k === :MissingValue
        print(io, "record ", r, ": neither a value nor a sum")
    elseif k === :MissingName
        print(io, "record ", r, ": neither a name nor a base name")
    elseif k === :InvalidName
        print(io, "record ", r, ": name must be [A-Za-z0-9][A-Za-z0-9:./_-]* (RFC 8428 4.5.1)")
    elseif k === :InvalidVersion
        print(io, "record ", r, ": bver must be a positive integer")
    elseif k === :UnsupportedVersion
        print(io, "record ", r, ": SenML version ", e.version, " is newer than 10 and must not be used")
    elseif k === :InconsistentVersion
        print(io, "record ", r, ": version differs from the rest of the pack")
    elseif k === :UnregisteredUnit
        print(io, "record ", r, ": unit is not in the SenML Units registry")
    elseif k === :RelativeTime
        print(io, "record ", r, ": relative time and no reference time to resolve it")
    elseif k === :Structure
        print(io, "invalid SenML ", f, ": ", e.reason)
    elseif k === :SchemaId
        if e.found === nothing
            print(io, "EXI header carries no options with schemaId \"a\"")
        else
            print(io, "EXI schemaId ", repr(e.found), " is not the RFC 8428 schema \"a\"")
        end
    elseif k === :Unrepresentable
        print(io, "cannot write as ", f, ": ", e.reason)
    elseif k === :Exi
        print(io, "EXI: ", e.reason)
    else
        print(io, k)
    end
end
