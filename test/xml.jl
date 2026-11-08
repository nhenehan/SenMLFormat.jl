# SenML XML reading and writing: rsenml-xml's tests, ported.

const X = SenML.Xml

const RFC_SECTION_7 = """<sensml xmlns="urn:ietf:params:xml:ns:senml">
  <senml bn="urn:dev:ow:10e2073a0108006:" bt="1.276020076001e+09"
  bu="A" bver="5" n="voltage" u="V" v="120.1"></senml>
  <senml n="current" t="-5" v="1.2"></senml>
  <senml n="current" t="-4" v="1.3"></senml>
  <senml n="current" t="-3" v="1.4"></senml>
  <senml n="current" t="-2" v="1.5"></senml>
  <senml n="current" t="-1" v="1.6"></senml>
  <senml n="current" v="1.7"></senml>
</sensml>"""

function xml_rfc_pack()
    records = [Record(bn = "urn:dev:ow:10e2073a0108006:", bt = 1.276020076001e9, bu = "A",
        bver = 5, n = "voltage", u = "V", v = 120.1)]
    for (t, v) in [(-5, 1.2), (-4, 1.3), (-3, 1.4), (-2, 1.5), (-1, 1.6)]
        push!(records, Record(n = "current", t = t, v = v))
    end
    push!(records, Record(n = "current", v = 1.7))
    return Pack(records)
end

const NS = "xmlns=\"urn:ietf:params:xml:ns:senml\""

one_record(attrs) = X.decode("<sensml $NS><senml n=\"a\" $attrs/></sensml>")

@testset "xml" begin
    @testset "RFC 8428 section 7" begin
        @test X.decode(xml_examples("7")[1]) == X.decode(RFC_SECTION_7)
        pack = X.decode(RFC_SECTION_7)
        @test pack == xml_rfc_pack()
        bytes = X.encode(pack)
        @test X.decode(bytes) == pack
        @test startswith(String(bytes), """<sensml xmlns="urn:ietf:params:xml:ns:senml"><senml bn="urn:dev:ow:10e2073a0108006:" bt="1276020076.001" bu="A" bver="5" n="voltage" u="V" v="120.1"/>""")
    end

    @testset "namespaces, prefixes and foreign attributes" begin
        doc = """<?xml version="1.0" encoding="UTF-8"?>
<!-- a comment --><?pi data?>
<s:sensml xmlns:s="urn:ietf:params:xml:ns:senml" xmlns:x="urn:other">
  <s:senml n="a" v="1" xml:lang="en" x:foo="ignored"/>
  <senml xmlns="urn:ietf:params:xml:ns:senml" n="b" vb="1"/>
</s:sensml>
<!-- trailing -->"""
        pack = X.decode(doc)
        @test length(pack) == 2
        @test isempty(pack[1].extensions)
        @test pack[2].value === true
        # A byte order mark and a CDATA section of whitespace are fine too.
        @test length(X.decode("﻿<sensml $NS><![CDATA[ ]]><senml n=\"a\" v=\"1\"/></sensml>")) == 1
    end

    @testset "references and attribute normalization" begin
        doc = "<sensml $NS><senml n=\"a\" vs=\"&lt;&amp;&quot;&#xE9;&#10;tab\there\" v2=\"  x  \"/></sensml>"
        pack = X.decode_unchecked(doc)
        @test pack[1].value == "<&\"é\ntab here"
        @test pack[1].extensions[1].value == "  x  "
        # The round trip keeps the newline through &#10;.
        @test X.decode_unchecked(X.encode(pack)) == pack
        @test X.decode("<sensml $NS><senml n=\"a\" vs=\"a\r\nb&#x+41;\"/></sensml>")[1].value == "a bA"
    end

    @testset "XSD types" begin
        @test one_record("v=\" 1.5E2 \"")[1].value === 150.0
        @test one_record("v=\"+.5\"")[1].value === 0.5
        @test one_record("v=\"-0\"")[1].value === -0.0
        @test one_record("v=\"1.\"")[1].value === 1.0
        @test one_record("vb=\"false\"")[1].value === false
        @test one_record("v=\"1\" bver=\"+7\"")[1].bver === UInt64(7)
        for (attrs, kind) in [("v=\"INF\"", :NonFinite), ("v=\"NaN\"", :NonFinite), ("v=\"1e400\"", :NonFinite),
                              ("v=\"1e\"", :WrongType), ("v=\"0x10\"", :WrongType), ("v=\".\"", :WrongType),
                              ("v=\"1\" bver=\"5.0\"", :WrongType), ("v=\"1\" bver=\"-1\"", :InvalidVersion),
                              ("v=\"1\" bver=\"2147483648\"", :WrongType), ("v=\"1\" bver=\"-\"", :WrongType),
                              ("vb=\"yes\"", :WrongType), ("vd=\"aGkgCg==\"", :InvalidBase64),
                              ("v=\"1\" crit_=\"x\"", :MustUnderstand), ("v=\"1\" vs=\"x\"", :MultipleValues),
                              ("v=\"1\" v=\"2\"", :DuplicateLabel)]
            @test (attrs, errkind(() -> one_record(attrs))) == (attrs, kind)
        end
    end

    @testset "structure is enforced" begin
        for bad in [
            """<sensml><senml n="a" v="1"/></sensml>""",
            """<sensml xmlns="urn:other"><senml n="a" v="1"/></sensml>""",
            """<senml $NS n="a" v="1"/>""",
            """<sensml $NS><other n="a" v="1"/></sensml>""",
            """<sensml $NS><senml n="a" v="1">text</senml></sensml>""",
            """<sensml $NS><senml n="a" v="1"><senml/></senml></sensml>""",
            """<sensml $NS>text<senml n="a" v="1"/></sensml>""",
            """<sensml $NS><senml n="a" v="1"></senm></sensml>""",
            """<!DOCTYPE sensml [<!ENTITY x "y">]><sensml $NS><senml n="a" v="1"/></sensml>""",
            """<?xml version="1.0" encoding="ISO-8859-1"?><sensml $NS><senml n="a" v="1"/></sensml>""",
            """<sensml $NS><senml n="a" v="1"/></sensml><sensml $NS/>""",
            """<sensml $NS><senml n="a" vs="&bogus;"/></sensml>""",
            """<sensml $NS><senml n="a" vs="&#0;"/></sensml>""",
            """<sensml $NS><senml n="a" vs="a<b"/></sensml>""",
            """<sensml $NS><senml 1n="a" v="1"/></sensml>""",
            """<sensml $NS><!-- a -- b --><senml n="a" v="1"/></sensml>""",
            """<sensml $NS><senml n="a" v="1" vs="\x01"/></sensml>""",
            """<sensml $NS> ]]> <senml n="a" v="1"/></sensml>""",
            """<sensml $NS><senml n="a"v="1"/></sensml>""",
            """<sensml $NS><?xml version="1.0"?><senml n="a" v="1"/></sensml>""",
        ]
            @test (bad, errkind(() -> X.decode(bad)) in (:Syntax, :Structure)) == (bad, true)
        end
        e = err(() -> X.decode([0xff, 0xfe]))
        @test e.kind === :Syntax && e.offset == 0
        e = err(() -> X.decode("<sensml $NS><senml n=\"a\" v=\"1\"/>"))
        @test e.kind === :Incomplete && e.format === :xml
        @test errkind(() -> X.decode("<sensml $NS/>")) === :EmptyPack
        @test errkind(() -> X.decode("")) === :Structure
    end

    @testset "writer escapes and refuses" begin
        pack = Pack([Record(n = "a", vs = "x\"<&\r\n\ty", extensions = ["ext-1" => [0xfb, 0xff]])])
        bytes = X.encode(pack)
        @test occursin("""vs="x&quot;&lt;&amp;&#13;&#10;&#9;y" ext-1="-_8\"""", String(copy(bytes)))
        @test X.decode(bytes)[1].value == pack[1].value
        @test errkind(() -> X.encode(Pack([Record(n = "a", vs = "\x01")]))) === :Unrepresentable
        @test errkind(() -> X.encode(Pack([Record(n = "a", v = 1, extensions = ["1bad" => true])]))) === :Unrepresentable
        @test errkind(() -> X.encode(Pack([Record(n = "a", v = 1, bver = 2^31)]))) === :UnsupportedVersion
        @test errkind(() -> X.encode_unchecked(Pack([Record(n = "a", v = 1, bver = 2^31)]))) === :Unrepresentable
        # Any XML name the decoder reads must be written back, not only ASCII ones
        # (U+FEFF is a NameChar).
        doc = "<sensml $NS><senml n=\"a\" v=\"1\" u﻿=\"V\" été=\"1\"/></sensml>"
        pack = X.decode(doc)
        @test X.decode(X.encode(pack)) == pack
    end

    @testset "record reader" begin
        r = X.RecordReader(RFC_SECTION_7)
        @test length(collect(r)) == 7
        X.finish(r)
    end

    @testset "stream encoder matches pack encoding" begin
        pack = xml_rfc_pack()
        io = IOBuffer()
        s = X.StreamEncoder()
        for r in pack
            X.record!(s, io, r)
        end
        X.finish!(s, io)
        @test take!(io) == X.encode(pack)
        io = IOBuffer()
        X.encode_record(io, pack[2], 2)
        @test String(take!(io)) == """<senml n="current" t="-5" v="1.2"/>"""
    end

    @testset "entity expansion is refused" begin
        bomb = """<!DOCTYPE sensml [<!ENTITY a "aaaaaaaaaa"><!ENTITY b "&a;&a;&a;&a;&a;&a;&a;&a;&a;&a;">]><sensml $NS><senml n="&b;" v="1"/></sensml>"""
        @test errkind(() -> X.decode(bomb)) === :Syntax
    end
end
