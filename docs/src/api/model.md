# Records and packs

The data model every format shares. A [`Pack`](@ref) is a vector of
[`Record`](@ref)s, each as written, base fields included.

```@docs
SenMLFormat
Record
Pack
Value
Extension
SenMLFormat.is_base_only
SenMLFormat.has_base_fields
SenMLFormat.has_regular_fields
base64url_encode
base64url_decode
SUPPORTED_VERSION
```
