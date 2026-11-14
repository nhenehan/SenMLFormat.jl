# SenML JSON reading and writing: rsenml-json's tests, ported.

const J = SenMLFormat.Json

@testset "json" begin
    @testset "RFC 8428 5.1.2 round trips byte for byte" begin
        text = """[{"bn":"urn:dev:ow:10e2073a01080063:","n":"voltage","u":"V","v":120.1},{"n":"current","u":"A","v":1.2}]"""
        pack = J.decode(text)
        @test length(pack) == 2
        @test J.encode(pack) == codeunits(text)
        @test J.decode(codeunits(text)) == pack
    end

    @testset "RFC 8428 5.1.5 data types" begin
        pack = J.decode("""[{"bn":"urn:dev:ow:10e2073a01080063:","n":"temp","u":"Cel","v":23.1},
             {"n":"label","vs":"Machine Room"},
             {"n":"open","vb":false},
             {"n":"nfc-reader","vd":"aGkgCg"}]""")
        @test [r.value for r in pack] == Any[23.1, "Machine Room", false, Vector{UInt8}("hi \n")]
    end

    @testset "numbers keep their value in shortest form" begin
        pack = J.decode("""[{"n":"a","bt":1.276020076001e+09,"v":20.0,"t":-5}]""")
        @test pack[1].bt == 1.276020076001e9
        @test String(J.encode(pack)) == """[{"bt":1276020076.001,"n":"a","t":-5,"v":20}]"""
    end

    @testset "escapes in strings and keys" begin
        input = "[{\"\\u006e\":\"a\\/b\",\"vs\":\"\\\"q\\\"\\n\\u00e9\\ud83d\\ude00\"}]"
        pack = J.decode(input)
        @test pack[1].n == "a/b"
        @test pack[1].value == "\"q\"\n\u00e9\U1f600"
        @test J.decode(J.encode(pack)) == pack
        # Control characters and DEL are written as \u00XX, `/` as is.
        p = Pack([Record(n = "a", vs = "\x01\x7f/\t\b\f")])
        @test String(J.encode(p)) == "[{\"n\":\"a\",\"vs\":\"\\u0001\\u007f/\\t\\b\\f\"}]"
        @test J.decode(J.encode(p)) == p
    end

    @testset "JSON grammar is enforced" begin
        for bad in [
            """[{"n":"a","v":+1}]""",
            """[{"n":"a","v":.5}]""",
            """[{"n":"a","v":01}]""",
            """[{"n":"a","v":1.}]""",
            """[{"n":"a","v":1e}]""",
            """[{"n":"a","v":NaN}]""",
            """[{"n":"a","v":1},]""",
            """[{"n":"a","v":1,}]""",
            """[{"n":"a" "v":1}]""",
            "[{\"n\":\"a\",\"vs\":\"\\x\"}]",
            "[{\"n\":\"a\",\"vs\":\"\\ud800\"}]",
            """{"n":"a","v":1}""",
            """[{"n":"a","v":1}] x""",
            """[{"n":"a","v":1}][]""",
            "[{\"n\":\"a\",\"vs\":\"tab\there\"}]",
            "[{\"n\":\"a\",\"vs\":\"\xff\"}]",
        ]
            @test errkind(() -> J.decode_unchecked(bad)) === :Syntax
        end
    end

    @testset "truncated input is incomplete" begin
        for cut in ["[", """[{"n":"a","v":1""", """[{"n":"a","v":1},""", """[{"n":"a","v":1}""", "[\"ab"]
            e = err(() -> J.decode_unchecked(cut))
            @test e !== nothing && e.kind === :Incomplete && e.format === :json
        end
    end

    @testset "record rules" begin
        e = err(() -> J.decode("""[{"n":"a","v":1,"crit_":true}]"""))
        @test e.kind === :MustUnderstand && e.record == 1 && e.label == "crit_"
        # Must-understand labels are refused even when their value is skipped.
        @test errkind(() -> J.decode("""[{"n":"a","v":1,"x_":[1,{"y":2}]}]""")) === :MustUnderstand
        @test errkind(() -> J.decode("""[{"n":"a","v":1,"vs":"x"}]""")) === :MultipleValues
        @test errkind(() -> J.decode("""[{"n":"a","n":"b","v":1}]""")) === :DuplicateLabel
        e = err(() -> J.decode("""[{"n":"a","v":"1"}]"""))
        @test e.kind === :WrongType && e.label == "v"
        @test errkind(() -> J.decode("""[{"n":"a","vd":"aGkgCg=="}]""")) === :InvalidBase64
        e = err(() -> J.decode("""[{"n":"a","v":1e400}]"""))
        @test e.kind === :NonFinite && e.label == "v"
        e = err(() -> J.decode("""[{"n":"a","v":1,"bver":11}]"""))
        @test e.kind === :UnsupportedVersion && e.version == 11
        @test errkind(() -> J.decode("[]")) === :EmptyPack
        @test J.decode("""[{"n":"a","v":1,"bver":5.0}]""")[1].bver === UInt64(5)
        @test errkind(() -> J.decode("""[{"n":"a","v":1,"bver":-0}]""")) === :InvalidVersion
    end

    @testset "unknown labels are kept or skipped" begin
        pack = J.decode("""[{"n":"a","v":1,"foo":"x","bar":2.5,"baz":true,"nested":{"a":[1,2]},"z":null}]""")
        @test [e.label for e in pack[1].extensions] == ["foo", "bar", "baz"]
        @test String(J.encode(pack)) == """[{"n":"a","v":1,"foo":"x","bar":2.5,"baz":true}]"""
    end

    @testset "reader yields records one by one" begin
        r = J.RecordReader(""" [ {"n":"a","v":1} , {"n":"b","v":2} ] """)
        @test [x.n for x in r] == ["a", "b"]
        J.finish(r)
    end

    @testset "stream decoder takes bytes as they come" begin
        text = codeunits("""[{"bn":"urn:dev:ow:10e2073a01080063","bt":1.320067464e+09,"bu":"%RH","v":21.2},{"t":10,"v":21.3},{"t":20,"vs":"a}]\\"b"}]""")
        d = J.StreamDecoder()
        got = Record[]
        for i in 1:3:length(text)
            push!(d, text[i:min(i + 2, end)])
            while (r = J.next_record!(d)) !== nothing
                push!(got, r)
            end
        end
        @test J.isfinished(d)
        J.finish(d)
        @test length(got) == 3
        @test got[3].value == "a}]\"b"
    end

    @testset "stream encoder matches pack encoding" begin
        pack = Pack([Record(bn = "dev:", n = "a", v = 1), Record(n = "b", v = 2)])
        io = IOBuffer()
        s = J.StreamEncoder()
        for r in pack
            J.record!(s, io, r)
        end
        J.finish!(s, io)
        @test take!(io) == J.encode(pack)
        io = IOBuffer()
        J.finish!(J.StreamEncoder(), io)
        @test String(take!(io)) == "[]"
    end

    @testset "unchecked encoding still refuses non-finite numbers" begin
        @test errkind(() -> J.encode_unchecked(Pack([Record(n = "a", v = NaN)]))) === :NonFinite
        @test errkind(() -> J.encode(Pack([Record(v = 1)]))) === :MissingName
        @test J.encode_unchecked(Pack([Record(v = 1)])) == codeunits("""[{"v":1}]""")
    end

    @testset "hostile input" begin
        deep = "[{\"n\":\"a\",\"v\":1,\"x\":" * "["^10_000 * "]"^10_000 * "}]"
        @test errkind(() -> J.decode(deep)) === :Syntax
    end
end
