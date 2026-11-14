# SenML EXI reading and writing: rsenml-exi's tests, and the EXIficient
# reference bytes, ported.

const EXIFormat = SenMLFormat.Exi.J  # the EXIFormat SenMLFormat.Exi is built on
const E = SenMLFormat.Exi

# RFC 8428 section 8, bit-packed (0x3f bytes).
const RFC_BIT_PACKED = hex("""
a0 30 0d 84 80 f3 ab 93 71 d3 23 2b b1 d3 7b b9
d1 89 83 29 91 81 b9 9b 09 81 89 81 c1 81 81 b1
99 d2 84 bb 37 b6 3a 30 b3 b2 90 1a b1 58 84 c0
33 04 b1 ba b9 39 32 b7 3a 10 1a 09 06 40 38""")

# RFC 8428 section 8, byte-aligned (0x31 bytes).
const RFC_BYTE_ALIGNED = hex("""
a0 00 48 80 6c 20 01 06 1d 75 72 6e 3a 64 65 76
3a 6f 77 3a 31 30 65 32 30 37 33 61 30 31 30 38
30 30 36 33 02 05 43 65 6c 01 00 e7 01 01 00 03
01""")

bit_packed_pack() = Pack([Record(bn = "urn:dev:ow:10e2073a01080063:", n = "voltage", u = "V", v = 120.1),
    Record(n = "current", u = "A", v = 1.2)])
byte_aligned_pack() = Pack([Record(n = "urn:dev:ow:10e2073a01080063", u = "Cel", v = 23.1)])

# A stream of the SenML schema written by EXIFormat directly, with chosen options.
function raw_stream(schema_id, include_options::Bool)
    J = EXIFormat
    opts = J.strict_options(; schema_id)
    enc = J.Encoder(E.Tables.GRAMMARS, opts; header = J.HeaderConfig(; include_options))
    ns = SenMLFormat.XML_NAMESPACE
    for ev in (J.StartDocument(), J.StartElement(ns, "sensml"), J.StartElement(ns, "senml"),
               J.Attribute("", "n", "a"), J.Attribute("", "v", "1"), J.EndElement(), J.EndElement(),
               J.EndDocument())
        push!(enc, ev)
    end
    return copy(J.finish!(enc))
end

@testset "exi" begin
    @testset "RFC 8428 section 8 both ways" begin
        @test length(RFC_BIT_PACKED) == 0x3f
        @test RFC_BIT_PACKED == hex_dumps("8")[1]
        @test E.decode(RFC_BIT_PACKED) == bit_packed_pack()
        @test E.encode(bit_packed_pack()) == RFC_BIT_PACKED
        @test length(RFC_BYTE_ALIGNED) == 0x31
        @test RFC_BYTE_ALIGNED == hex_dumps("8")[2]
        @test E.decode(RFC_BYTE_ALIGNED) == byte_aligned_pack()
        @test E.encode(byte_aligned_pack(); alignment = :byte_aligned) == RFC_BYTE_ALIGNED
    end

    @testset "the hand-coded sensor value of section 8" begin
        # "replacing the value 0xe7 0x01 at location 0x2b and 0x2c with the current
        # temperature" in tenths of a degree: try 55.0 -> 550.
        bytes = copy(RFC_BYTE_ALIGNED)
        tenths = 550
        bytes[0x2b+1] = (tenths & 0x7f) | 0x80
        bytes[0x2c+1] = tenths >> 7
        @test E.decode(bytes)[1].value === 55.0
    end

    @testset "every field and value type round trips" begin
        pack = Pack([
            Record(bn = "urn:dev:ow:10e2073a01080063:", bt = 1.276020076001e9, bu = "A", bv = 0.5,
                bs = -2, bver = 5, n = "temp", u = "Cel", v = 23.1, s = 1e300, t = -5, ut = 60),
            Record(n = "label", vs = "Machine Room"),
            Record(n = "open", vb = false),
            Record(n = "nfc-reader", vd = Vector{UInt8}("hi \n")),
            Record(n = "tiny", v = 5e-324),
        ])
        for alignment in (:bit_packed, :byte_aligned)
            @test E.decode(E.encode(pack; alignment)) == pack
        end
    end

    @testset "extensions are dropped or refused" begin
        pack = Pack([Record(n = "a", v = 1, extensions = ["foo" => true])])
        @test isempty(E.decode(E.encode(pack))[1].extensions)
        @test errkind(() -> E.encode(pack; extensions = :error)) === :Unrepresentable
        @test_throws ArgumentError E.encode(pack; extensions = :keep)
        @test_throws ArgumentError E.encode(pack; alignment = :compressed)
    end

    @testset "cookie" begin
        bytes = E.encode(bit_packed_pack(); cookie = true)
        @test bytes[1:4] == codeunits("\$EXI")
        @test E.decode(bytes) == bit_packed_pack()
    end

    @testset "schemaId is checked" begin
        e = err(() -> E.decode(raw_stream("b", true)))
        @test e.kind === :SchemaId && e.found == "b"
        e = err(() -> E.decode(raw_stream(nothing, true)))
        @test e.kind === :SchemaId && e.found === nothing
        # Options out of band: refused unless the caller gives them.
        bare = raw_stream("a", false)
        e = err(() -> E.decode(bare))
        @test e.kind === :SchemaId && e.found === nothing
        @test length(E.decode(bare; out_of_band = :bit_packed)) == 1
    end

    @testset "malformed streams" begin
        @test errkind(() -> E.decode([0x00, 0x01])) === :Syntax
        e = err(() -> E.decode(RFC_BIT_PACKED[1:end÷2]))
        @test e.kind === :Incomplete && e.format === :exi
        @test errkind(() -> E.decode(UInt8[])) === :Incomplete
    end

    @testset "writer and reader work record by record" begin
        s = E.StreamEncoder()
        for r in bit_packed_pack()
            E.record!(s, r)
        end
        bytes = E.finish!(s)
        @test bytes == RFC_BIT_PACKED
        r = E.RecordReader(bytes)
        @test [x.n for x in r] == ["voltage", "current"]
        E.finish(r)
    end

    @testset "bver must fit xs:int" begin
        @test errkind(() -> E.encode(Pack([Record(n = "a", v = 1, bver = 10)]))) === :ok
        big = Pack([Record(n = "a", v = 1, bver = 2^40)])
        # Validation refuses it first (versions above 10).
        @test errkind(() -> E.encode(big)) === :UnsupportedVersion
        @test errkind(() -> E.encode_unchecked(big)) === :Unrepresentable
    end

    @testset "unchecked encoding skips validation only" begin
        pack = bit_packed_pack()
        @test E.encode_unchecked(pack) == E.encode(pack)
        # A record with neither value nor sum: invalid SenML, but EXI can carry it.
        invalid = Pack([Record(n = "a", t = 1)])
        e = err(() -> E.encode(invalid))
        @test e.kind === :MissingValue && e.record == 1
        @test E.decode_unchecked(E.encode_unchecked(invalid)) == invalid
        # Values EXI cannot carry are still refused.
        @test errkind(() -> E.encode_unchecked(Pack([Record(n = "a", v = NaN)]))) === :NonFinite
    end

    @testset "negative zero becomes zero" begin
        back = E.decode(E.encode(Pack([Record(n = "a", v = -0.0)])))
        @test back[1].value === 0.0
    end

    @testset "every case matches EXIficient byte for byte" begin
        manifest = exificient_manifest()
        checked = 0
        for c in cases()
            pack = SenMLFormat.Json.decode(unhex(c["json"]))
            for (profile, alignment) in (("bp", :bit_packed), ("ba", :byte_aligned))
                reference = read(joinpath(FIXTURES, "exificient", "$(c["name"]).$profile.exi"))
                @test any(m -> m["case"] == c["name"] && m["profile"] == profile &&
                    parse(Int, m["bytes"]) == length(reference), manifest)
                @test (c["name"], profile, E.encode(pack; alignment) == reference) == (c["name"], profile, true)
                @test same_pack(E.decode(reference), exi_view(pack))
                checked += 1
            end
        end
        @test checked == 32
    end
end
