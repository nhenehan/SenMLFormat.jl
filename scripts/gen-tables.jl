# Writes (or, with --check, verifies) src/generated/senml_tables.jl: the EXI grammar
# tables of the RFC 8428 schema (section 8,
# https://www.rfc-editor.org/rfc/rfc8428#section-8, which scripts/fetch-standards.sh
# takes out of the RFC as senml.xsd), made by EXIFormat.SchemaGen, with
# schemaId "a" (RFC 8428 section 8) so that EXIFormat itself refuses a stream that
# names another schema. Run through scripts/gen-tables.sh.
using EXIFormat

const ROOT = dirname(@__DIR__)
const STANDARDS = readchomp(`$(joinpath(ROOT, "scripts", "fetch-standards.sh")) --print-dir`)
const XSD = joinpath(STANDARDS, "senml.xsd")
isfile(XSD) || error("$XSD is missing: run scripts/fetch-standards.sh")
const OUT = joinpath(ROOT, "src", "generated", "senml_tables.jl")

g = EXIFormat.with_schema_id(EXIFormat.compile_files(XSD), "a")
text = EXIFormat.SchemaGen.render(g; name = "GRAMMARS", module_name = "Tables", source = "senml.xsd (schemaId \"a\")")

if "--check" in ARGS
    if isfile(OUT) && read(OUT, String) == text
        println("generated tables ok")
        exit(0)
    end
    println(stderr, "STALE    src/generated/senml_tables.jl: run scripts/gen-tables.sh")
    exit(1)
end
mkpath(dirname(OUT))
write(OUT, text)
println("wrote src/generated/senml_tables.jl")
