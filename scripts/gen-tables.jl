# Writes (or, with --check, verifies) src/generated/senml_tables.jl: the EXI grammar
# tables of the RFC 8428 schema (spec/senml.xsd), made by JExi.SchemaGen, with
# schemaId "a" (RFC 8428 section 8) so that JExi itself refuses a stream that
# names another schema. Run through scripts/gen-tables.sh.
using JExi

const ROOT = dirname(@__DIR__)
const XSD = joinpath(ROOT, "spec", "senml.xsd")
const OUT = joinpath(ROOT, "src", "generated", "senml_tables.jl")

g = JExi.with_schema_id(JExi.compile_files(XSD), "a")
text = JExi.SchemaGen.render(g; name = "GRAMMARS", module_name = "Tables", source = "senml.xsd (schemaId \"a\")")

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
