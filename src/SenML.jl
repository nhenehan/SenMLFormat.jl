"""
    SenML

Sensor Measurement Lists ([RFC 8428](https://www.rfc-editor.org/rfc/rfc8428)):
records and packs, read and written as JSON, CBOR, XML and EXI. The Julia twin of
the Rust library rsenml: same rules, same bytes.

- [`Record`](@ref), [`Pack`](@ref), [`Extension`](@ref): records as written, base
  fields included.
- [`validate`](@ref) / [`Validator`](@ref): the rules of section 4.
- [`resolve`](@ref) / [`Resolver`](@ref): records with the base fields applied
  (section 4.6).
- [`lookup_unit`](@ref), [`UNITS`](@ref): the units registry (section 12.1).
- [`RecordSelector`](@ref): `rec=` fragment identifiers (section 9).
- [`MediaType`](@ref): media types and CoAP Content-Formats (sections 12.3, 12.5).
- `SenML.Json`, `SenML.Cbor`: the JSON (section 5) and CBOR (section 6) formats.
"""
module SenML

export Record, Extension, Pack, Value, ResolvedRecord, SenMLError
export validate, Validator, check!, finish, valid_name, SUPPORTED_VERSION
export resolve, Resolver, resolve!, set_now!, to_record, is_relative_time,
    ABSOLUTE_TIME_THRESHOLD
export Unit, UNITS, lookup_unit
export RecordSelector, selects, selected
export MediaType, SENML_JSON, SENSML_JSON, SENML_CBOR, SENSML_CBOR, SENML_XML,
    SENSML_XML, SENML_EXI, SENSML_EXI, content_type, coap_content_format, media_format,
    is_streaming, media_type
export base64url_encode, base64url_decode
export XML_NAMESPACE, EXI_SCHEMA_ID

"""
The XML namespace of SenML
([RFC 8428 section 12.4](https://www.rfc-editor.org/rfc/rfc8428#section-12.4)).
"""
const XML_NAMESPACE = "urn:ietf:params:xml:ns:senml"

"""
The EXI schemaId of the RFC 8428 schema. The EXI header options must carry it
([RFC 8428 section 8](https://www.rfc-editor.org/rfc/rfc8428#section-8)).
"""
const EXI_SCHEMA_ID = "a"

include("core/error.jl")
include("core/label.jl")
include("core/record.jl")
include("core/builder.jl")
include("core/units.jl")
include("core/validate.jl")
include("core/resolve.jl")
include("core/fragment.jl")
include("core/media.jl")
include("core/base64url.jl")
include("core/number.jl")

end # module
