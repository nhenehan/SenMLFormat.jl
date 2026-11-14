# SenML CBOR reading and writing: rsenml-cbor's tests, ported.

const C = SenMLFormat.Cbor

# RFC 8428 section 6, the hex dump (0xc3 bytes).
const RFC_SECTION_6 = hex("""
87 a7 21 78 1b 75 72 6e 3a 64 65 76 3a 6f 77 3a
31 30 65 32 30 37 33 61 30 31 30 38 30 30 36 3a
22 fb 41 d3 03 a1 5b 00 10 62 23 61 41 20 05 00
67 76 6f 6c 74 61 67 65 01 61 56 02 fb 40 5e 06
66 66 66 66 66 a3 00 67 63 75 72 72 65 6e 74 06
24 02 fb 3f f3 33 33 33 33 33 33 a3 00 67 63 75
72 72 65 6e 74 06 23 02 fb 3f f4 cc cc cc cc cc
cd a3 00 67 63 75 72 72 65 6e 74 06 22 02 fb 3f
f6 66 66 66 66 66 66 a3 00 67 63 75 72 72 65 6e
74 06 21 02 f9 3e 00 a3 00 67 63 75 72 72 65 6e
74 06 20 02 fb 3f f9 99 99 99 99 99 9a a3 00 67
63 75 72 72 65 6e 74 06 00 02 fb 3f fb 33 33 33
33 33 33""")

# The section 6 example in diagnostic notation, as a pack.
function rfc_pack()
    records = [Record(bn = "urn:dev:ow:10e2073a0108006:", bt = 1.276020076001e9, bu = "A",
        bver = 5, n = "voltage", u = "V", v = 120.1)]
    for (t, v) in [(-5, 1.2), (-4, 1.3), (-3, 1.4), (-2, 1.5), (-1, 1.6), (0, 1.7)]
        push!(records, Record(n = "current", t = t, v = v))
    end
    return Pack(records)
end

@testset "cbor" begin
    @testset "RFC 8428 section 6 both ways" begin
        @test length(RFC_SECTION_6) == 0xc3
        @test RFC_SECTION_6 == hex_dumps("6")[1]
        @test C.decode(RFC_SECTION_6) == rfc_pack()
        @test C.encode(rfc_pack()) == RFC_SECTION_6
    end

    @testset "numbers take the smallest exact form" begin
        pack = Pack([Record(n = "a", v = 1.5, t = 1_700_000_000, s = 0.1, ut = 0.5)])
        bytes = C.encode(pack)
        # map(5): 0:"a", 6:1700000000 (u32), 7:0.5 (f16), 5:0.1 (f64), 2:1.5 (f16)
        @test bytes == hex("81 a5 00 61 61 06 1a 65 53 f1 00 07 f9 38 00 05 fb 3f b9 99 99 99 99 99 9a 02 f9 3e 00")
        @test C.decode(bytes) == pack
        # f32 when exact and not representable as half.
        @test C.encode(Pack([Record(n = "a", v = 100_000.5)])) == hex("81 a2 00 61 61 02 fa 47 c3 50 40")
        # -0.0 is a half float, not the integer 0; negative integers use major type 1.
        @test C.encode(Pack([Record(n = "a", v = -0.0)])) == hex("81 a2 00 61 61 02 f9 80 00")
        @test C.encode(Pack([Record(n = "a", v = -24)])) == hex("81 a2 00 61 61 02 37")
        @test C.encode(Pack([Record(n = "a", v = 1e300)]))[end-8:end] == vcat(0xfb, reinterpret(UInt8, [hton(reinterpret(UInt64, 1e300))]))
    end

    @testset "every numeric form is read" begin
        # v as u8, negative int, f16, f32, f64, tag 4 decimal fraction 4(-2, 2345) = 23.45, u64
        for (value, expected) in [("18 17", 23.0), ("38 16", -23.0), ("f9 3e 00", 1.5),
                                  ("fa 41 b8 cc cd", Float64(23.1f0)), ("fb 40 37 19 99 99 99 99 9a", 23.1),
                                  ("c4 82 21 19 09 29", 23.45), ("1b 00 00 00 01 00 00 00 00", 4_294_967_296.0),
                                  ("3b ff ff ff ff ff ff ff ff", -18446744073709551616.0)]
            pack = C.decode(hex("81 a2 00 61 61 02 " * value))
            @test pack[1].value === expected
        end
    end

    @testset "text keys spelling registered labels are ignored" begin
        # {0: "a", 2: 1, "v": 2, "bn": "x"}: the integer key 2 is the value; the
        # text keys are unrecognized fields (RFC 8428 4.4) and are dropped.
        pack = C.decode(hex("81 a4 00 61 61 02 01 61 76 02 62 62 6e 61 78"))
        @test pack[1].value === 1.0
        @test pack[1].bn === nothing
        @test isempty(pack[1].extensions)
    end

    @testset "record rules" begin
        bad(h) = errkind(() -> C.decode(hex(h)))
        # text key "v" is not Value in CBOR: ignored, so this record has no value
        @test bad("81 a2 00 61 61 61 76 01") === :MissingValue
        @test bad("81 a3 00 61 61 02 01 62 78 5f f5") === :MustUnderstand
        # bver as a float is not allowed (section 6)
        e = err(() -> C.decode(hex("81 a3 00 61 61 02 01 20 f9 45 00")))
        @test e.kind === :WrongType && e.label == "bver"
        @test bad("81 a3 00 61 61 00 61 62 02 01") === :DuplicateLabel
        @test bad("81 a3 00 61 61 02 01 04 f5") === :MultipleValues
        @test bad("81 a2 00 61 61 03 41 00") === :WrongType
        @test bad("81 a2 00 61 61 02 f9 7e 00") === :NonFinite
        @test bad("9f a2 00 61 61 02 01 ff") === :Syntax  # SenML must be a definite array
        @test bad("81 a2 00 61 61 02 01 00") === :Syntax  # trailing bytes
        e = err(() -> C.decode(hex("81 a2 00 61 61 02")))
        @test e.kind === :Incomplete && e.format === :cbor
        @test bad("81 a2 00 7f 61 61 ff 02 01") === :Syntax  # indefinite text key
        @test bad("81 a2 00 61 61 02 c5 82 21 19 09 29") === :WrongType  # tag 5 is not a number
        @test bad("81 a2 00 61 61 02 c4 83 21 19 09 29 00") === :Syntax  # a 3-element decimal fraction
        @test bad("81 a2 00 61 ff 02 01") === :Syntax  # text that is not UTF-8
        # Reserved additional info: not a number (as minicbor classifies it), and
        # not a valid map key.
        @test bad("81 a2 00 61 61 02 1c") === :WrongType
        @test bad("81 a2 00 61 61 1c 01") === :Syntax
    end

    @testset "unknown integer keys are ignored and text extensions kept" begin
        # key 9 (not in Table 4) and key -7 ignored; "foo": h'01' kept, "bar": [1] skipped
        pack = C.decode_unchecked(hex("81 a6 00 61 61 02 01 09 f5 26 61 78 63 66 6f 6f 41 01 63 62 61 72 81 01"))
        @test pack[1].extensions == [Extension("foo", [0x01])]
        # Records may be indefinite-length maps; skipped values may be nested and tagged.
        pack = C.decode(hex("81 bf 00 61 61 02 01 63 62 61 72 c1 9f 81 a0 7f 61 78 ff ff ff"))
        @test pack[1].n == "a" && isempty(pack[1].extensions)
    end

    @testset "large packs and integer times" begin
        pack = Pack([Record(n = "sensor", t = 1_700_000_000 + i, v = i) for i in 0:99])
        @test C.decode(C.encode(pack)) == pack
    end

    @testset "SenSML uses an indefinite array" begin
        pack = rfc_pack()
        bytes = C.encode_sensml(pack)
        @test first(bytes) == 0x9f && last(bytes) == 0xff
        @test C.decode_sensml(bytes) == pack
        @test errkind(() -> C.decode(bytes)) === :Syntax
        # SenSML readers also accept a definite array.
        @test C.decode_sensml(C.encode(pack)) == pack
        io = IOBuffer()
        s = C.StreamEncoder()
        for r in pack
            C.record!(s, io, r)
        end
        C.finish!(s, io)
        @test take!(io) == bytes
        io = IOBuffer()
        C.finish!(C.StreamEncoder(), io)
        @test take!(io) == [0x9f, 0xff]
    end

    @testset "stream decoder takes bytes as they come" begin
        bytes = C.encode_sensml(rfc_pack())
        d = C.StreamDecoder()
        got = Record[]
        for i in 1:5:length(bytes)
            push!(d, bytes[i:min(i + 4, end)])
            while (r = C.next_record!(d)) !== nothing
                push!(got, r)
            end
        end
        @test C.isfinished(d)
        C.finish(d)
        @test Pack(got) == rfc_pack()
    end

    @testset "reader" begin
        @test length(collect(C.RecordReader(RFC_SECTION_6))) == 7
    end

    @testset "hostile input" begin
        deep = vcat(hex("81 a3 00 61 61 02 01 63 66 6f 6f"), fill(0x81, 100_000), 0x00)
        @test errkind(() -> C.decode(deep)) === :ok
        @test errkind(() -> C.decode(hex("9b ff ff ff ff ff ff ff ff"))) === :Incomplete
        @test errkind(() -> C.decode(hex("81 a1 08 5a ff ff ff ff"))) === :Incomplete
        @test errkind(() -> C.decode(hex("81 a2 00 61 61 63 66 6f 6f 9b ff ff ff ff ff ff ff ff"))) === :Incomplete
    end
end

@testset "cross format" begin
    for c in cases()
        pack = SenMLFormat.Json.decode(unhex(c["json"]))
        @test same_pack(C.decode(C.encode(pack)), pack)
        @test same_pack(C.decode_sensml(C.encode_sensml(pack)), pack)
        @test SenMLFormat.Json.encode(C.decode(C.encode(pack))) == unhex(c["json"])
        @test C.encode_unchecked(pack) == C.encode(pack)
    end
    # JSON -> CBOR -> XML -> EXI -> JSON gives the same JSON bytes.
    for c in cases()
        json = SenMLFormat.Json.encode(exi_view(SenMLFormat.Json.decode(unhex(c["json"]))))
        a = SenMLFormat.Json.decode(json)
        b = C.decode(C.encode(a))
        x = SenMLFormat.Xml.decode(SenMLFormat.Xml.encode(b))
        d = SenMLFormat.Exi.decode(SenMLFormat.Exi.encode(x))
        @test SenMLFormat.Json.encode(d) == json
    end
    # Negative zero survives JSON and CBOR.
    p = Pack([Record(n = "a", v = -0.0)])
    @test same_pack(SenMLFormat.Json.decode(SenMLFormat.Json.encode(p)), p)
    @test same_pack(C.decode(C.encode(p)), p)
    # Extensions survive JSON and CBOR.
    json = codeunits("""[{"n":"a","v":1,"origin":"lab-3","weight":0.5,"calibrated":true}]""")
    p = SenMLFormat.Json.decode(json)
    @test C.decode(C.encode(p)) == p
    @test SenMLFormat.Json.encode(C.decode(C.encode(p))) == json
end
