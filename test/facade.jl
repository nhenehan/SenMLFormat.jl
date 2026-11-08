# decode/encode by media type (rsenml's facade tests), and the full byte sweep:
# every test case, in all eight media types, gives rsenml's bytes and reads
# rsenml's bytes back to the same pack.

# The cases.tsv column with rsenml's bytes for each media type.
const MEDIA_COLUMN = Dict(
    SENML_JSON => "json", SENSML_JSON => "json",
    SENML_CBOR => "cbor", SENSML_CBOR => "cbor_sensml",
    SENML_XML => "xml", SENSML_XML => "xml",
    SENML_EXI => "exi_bp", SENSML_EXI => "exi_bp",
)

@testset "facade" begin
    @testset "every case in every media type equals rsenml" begin
        for c in cases(), m in instances(MediaType)
            pack = SenML.Json.decode(unhex(c["json"]))
            want = unhex(c[MEDIA_COLUMN[m]])
            @test (c["name"], m, SenML.encode(m, pack)) == (c["name"], m, want)
            @test (c["name"], m, SenML.encode_unchecked(m, pack)) == (c["name"], m, want)
            view = media_format(m) === :exi ? exi_view(pack) : pack
            @test (c["name"], m, same_pack(SenML.decode(m, want), view)) == (c["name"], m, true)
        end
    end

    @testset "strings are read as UTF-8 bytes" begin
        text = """[{"n":"a","v":1}]"""
        @test SenML.decode(SENML_JSON, text) == SenML.decode(SENML_JSON, codeunits(text))
        xml = String(SenML.encode(SENML_XML, SenML.decode(SENML_JSON, text)))
        @test SenML.decode(SENML_XML, SubString(xml, 1)) == SenML.decode(SENML_JSON, text)
    end

    @testset "SenSML CBOR is an indefinite array; SenML CBOR is not" begin
        p = Pack([Record(n = "a", v = 1)])
        @test first(SenML.encode(SENSML_CBOR, p)) == 0x9f
        @test first(SenML.encode(SENML_CBOR, p)) == 0x81
        @test errkind(() -> SenML.decode(SENML_CBOR, SenML.encode(SENSML_CBOR, p))) !== :ok
        @test SenML.decode(SENSML_CBOR, SenML.encode(SENML_CBOR, p)) == p
    end

    @testset "checked and unchecked" begin
        bad = Pack([Record(n = "a")])  # no value
        for m in instances(MediaType)
            @test errkind(() -> SenML.encode(m, bad)) === :MissingValue
            @test errkind(() -> SenML.encode_unchecked(m, bad)) === :ok
        end
        nan = Pack([Record(n = "a", v = NaN)])
        for m in instances(MediaType)
            @test errkind(() -> SenML.encode_unchecked(m, nan)) !== :ok
        end
    end

    @testset "media type from a content type" begin
        bytes = SenML.encode(SENML_CBOR, Pack([Record(n = "a", v = 1)]))
        @test SenML.decode(media_type("application/senml+cbor"), bytes) == Pack([Record(n = "a", v = 1)])
        @test SenML.decode(media_type(112), bytes) == Pack([Record(n = "a", v = 1)])
    end
end
