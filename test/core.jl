# The data model: rsenml-core's unit tests, ported.

errkind(f) =
    try
        f()
        :ok
    catch e
        e isa SenMLError || rethrow()
        e.kind
    end

@testset "core" begin
    @testset "labels" begin
        for l in 1:15
            @test SenML.label_from_text(SenML.label_text(l)) == l
            @test SenML.label_from_cbor(SenML.LABEL_CBOR[l]) == l
            @test SenML.is_base_label(l) == SenML.is_base_label_text(SenML.label_text(l))
        end
        @test sort(collect(SenML.LABEL_CBOR)) == collect(-6:8)
        @test SenML.label_from_cbor(9) == 0
        @test SenML.label_from_cbor(-7) == 0
        @test SenML.label_from_text("x") == 0
        @test SenML.is_must_understand("foo_")
    end

    @testset "records" begin
        r = Record(bn = "dev/", n = "a", v = 1)
        @test r.value === 1.0
        @test Record(vs = "x").value == "x"
        @test Record(vb = true).value === true
        @test Record(vd = [0x01]).value == [0x01]
        @test Record(value = 2).value === 2.0
        @test_throws ArgumentError Record(v = 1, vs = "x")
        @test Record(bver = 5).bver === UInt64(5)
        r = Record(n = "a", v = 1, extensions = ["foo" => "x", Extension("bar", 2)])
        @test r.extensions == [Extension("foo", "x"), Extension("bar", 2.0)]
        # A vb is never a v, although true == 1.0 in Julia.
        @test Record(n = "a", vb = true) != Record(n = "a", v = 1)
        @test Record(n = "a", v = -0.0) == Record(n = "a", v = 0.0)
        @test hash(Record(n = "a", v = -0.0)) == hash(Record(n = "a", v = 0.0))
        @test SenML.is_base_only(Record(bn = "x"))
        @test !SenML.is_base_only(Record(bn = "x", n = "a"))
        @test !SenML.is_base_only(Record(extensions = ["x" => 1]))
        @test SenML.is_base_only(Record(extensions = ["bx" => 1]))
        p = Pack([r])
        push!(p, Record(n = "b", v = 2))
        @test length(p) == 2
        @test p[2].n == "b"
        @test Pack() == Pack(Record[])
    end

    @testset "builder" begin
        b = SenML.RecordBuilder(3)
        SenML.set!(b, SenML.L_N, "a")
        e = try SenML.set!(b, SenML.L_N, "b"); nothing catch e; e end
        @test e isa SenMLError && e.kind === :DuplicateLabel && e.record == 3 && e.label == "n"
        SenML.set!(b, SenML.L_V, 1.0)
        @test errkind(() -> SenML.set!(b, SenML.L_VB, true)) === :MultipleValues
        @test errkind(() -> SenML.extension!(b, "foo_", true)) === :MustUnderstand
        SenML.extension!(b, "foo", true)
        @test errkind(() -> SenML.extension!(b, "foo", true)) === :DuplicateLabel
        @test errkind(() -> SenML.extension!(b, "v", true)) === :DuplicateLabel

        b = SenML.RecordBuilder(1)
        @test errkind(() -> SenML.set!(b, SenML.L_T, "1")) === :WrongType
        @test errkind(() -> SenML.set!(b, SenML.L_BVER, 5.5)) === :InvalidVersion
        @test errkind(() -> SenML.set!(b, SenML.L_S, NaN)) === :NonFinite
        b = SenML.RecordBuilder(1)
        SenML.set!(b, SenML.L_BVER, 5.0)
        SenML.set!(b, SenML.L_T, UInt64(7))
        r = SenML.build(b)
        @test r.bver === UInt64(5)
        @test r.t === 7.0
    end

    @testset "validation" begin
        v(records...; kw...) = errkind(() -> validate(Pack(collect(records)); kw...))
        # RFC 8428 section 5.1.7: a base-only record is context.
        @test v(Record(bn = "urn:dev:ow:10e2073a01080063:"), Record(n = "temp", u = "Cel", v = 23.1)) === :ok
        @test v(Record(n = "a", t = 1)) === :MissingValue
        @test v(Record(n = "a", s = 1)) === :ok
        @test v(Record(v = 1)) === :MissingName
        @test v(Record(n = "-x", v = 1)) === :InvalidName
        @test v(Record(n = "a b", v = 1)) === :InvalidName
        @test v(Record(bn = "", v = 1)) === :InvalidName
        @test v() === :EmptyPack

        r(ver) = Record(n = "a", v = 1, bver = ver)
        @test v(r(5), r(nothing)) === :ok
        @test v(r(5), r(5)) === :ok
        @test v(r(5), r(10)) === :InconsistentVersion
        @test v(r(nothing), r(5)) === :InconsistentVersion
        @test v(r(nothing), r(10)) === :ok
        @test v(r(11)) === :UnsupportedVersion
        @test v(r(0)) === :InvalidVersion

        @test v(Record(n = "a", v = 1, extensions = ["crit_" => true])) === :MustUnderstand
        @test v(Record(n = "a", v = 1, extensions = ["v" => true])) === :InvalidLabel
        @test v(Record(n = "a", v = 1, extensions = ["x" => 1, "x" => 2])) === :DuplicateLabel
        @test v(Record(n = "a", v = Inf)) === :NonFinite
        @test v(Record(n = "a", u = "furlong", v = 1)) === :ok
        @test v(Record(n = "a", u = "furlong", v = 1); registered_units = true) === :UnregisteredUnit
        @test v(Record(n = "a", u = "Cel", v = 1); registered_units = true) === :ok
        @test v(Record(bu = "furlong", n = "a", v = 1); registered_units = true) === :UnregisteredUnit
    end

    @testset "name rule matches the concatenation check" begin
        # Base names are set, changed and emptied along the pack; the validator
        # must agree with valid_name(bn, n), the rule as the spec writes it.
        alphabet = ["", "a", "Z9", "-x", ":", "dev/", "a b", "_", "é", "0.1"]
        state = UInt64(0x12345678)
        function next!()
            state ⊻= state << 13
            state ⊻= state >> 7
            state ⊻= state << 17
            return state
        end
        ok = true
        for _ in 1:5000
            bn = nothing
            for _ in 1:4
                x = next!()
                rbn = nothing
                if x % 3 == 0
                    rbn = alphabet[(x >> 8) % length(alphabet) + 1]
                    bn = rbn
                end
                name = (x >> 16) % 4 == 0 ? nothing : alphabet[(x >> 24) % length(alphabet) + 1]
                val = Validator()
                bn === nothing || check!(val, Record(bn = bn))
                got = errkind(() -> check!(val, Record(bn = rbn, n = name, v = 1)))
                want = name === nothing && bn === nothing ? :MissingName :
                    valid_name(something(bn, ""), something(name, "")) ? :ok : :InvalidName
                ok &= got === want
            end
        end
        @test ok
    end

    @testset "resolution" begin
        # Section 5.1.3, resolved in section 5.1.4.
        pack = Pack([
            Record(bn = "urn:dev:ow:10e2073a01080063", bu = "%RH", bt = 1.320067464e9, v = 20),
            Record(u = "lon", v = 24.30621),
            Record(u = "lat", v = 60.07965),
            Record(t = 60, v = 20.3),
            Record(u = "%EL", t = 150, v = 98),
        ])
        res = resolve(pack)
        @test all(r -> r.name == "urn:dev:ow:10e2073a01080063", res)
        @test [r.unit for r in res] == ["%RH", "lon", "lat", "%RH", "%EL"]
        @test [r.time for r in res] == [1.320067464e9, 1.320067464e9, 1.320067464e9, 1.320067524e9, 1.320067614e9]
        @test all(r -> r.version === nothing, res)

        pack = Pack([
            Record(bn = "dev/", bv = 100, bs = 10, bver = 5, n = "a", v = 1, t = -1),
            Record(n = "b", vs = "x", t = -2),
        ])
        @test errkind(() -> resolve(pack)) === :RelativeTime
        res = resolve(pack; now = 1000)
        @test res[1].name == "dev/b"
        @test res[1].time == 998
        @test res[1].value == "x"
        @test res[1].sum == 10
        @test res[2].value === 101.0
        @test res[2].version === UInt64(5)
        rec = to_record(res[2])
        @test rec.bver === UInt64(5)
        @test rec.n == "dev/a"

        # Base extensions are dropped, regular ones kept; Resolver works record by record.
        r = Resolver(; now = 0)
        @test resolve!(r, Record(bn = "x/", extensions = ["bfoo" => 1])) === nothing
        rr = resolve!(r, Record(n = "a", v = 1, t = 2^28, extensions = ["foo" => 1, "bbar" => 2]))
        @test rr.name == "x/a"
        @test rr.extensions == [Extension("foo", 1)]
        @test is_relative_time(2^28 - 1) && !is_relative_time(ABSOLUTE_TIME_THRESHOLD)
    end

    @testset "units" begin
        @test length(UNITS) == 58
        @test lookup_unit("Cel").deprecated == false
        @test lookup_unit("cel") === nothing
        @test lookup_unit("%").deprecated == true
        @test lookup_unit("furlong") === nothing
        @test allunique(u.symbol for u in UNITS)
    end

    @testset "fragments" begin
        sel(f, len) = selected(parse(RecordSelector, f), len)
        @test sel("rec=3", 25) == [3]
        @test sel("rec=3-6", 25) == [3, 4, 5, 6]
        @test sel("rec=19-*", 21) == [19, 20, 21]
        @test sel("rec=3,5", 25) == [3, 5]
        @test sel("#rec=3-5,10,19-*", 20) == [3, 4, 5, 10, 19, 20]
        @test sel("rec=30", 25) == Int[]
        for f in ["rec=", "rec=0", "rec=a", "rec=5-3", "row=1", "rec=1,", "rec=-3", "rec=+1"]
            @test tryparse(RecordSelector, f) === nothing
        end
        @test_throws ArgumentError parse(RecordSelector, "rec=0")
        @test selects(parse(RecordSelector, "rec=2"), 2, 3)
    end

    @testset "media types" begin
        for m in instances(MediaType)
            @test media_type(content_type(m)) === m
            @test media_type(coap_content_format(m)) === m
            @test media_type(media_format(m), is_streaming(m)) === m
        end
        @test media_type("Application/SenML+JSON; charset=utf-8") === SENML_JSON
        @test media_type(50) === nothing
        @test media_type("application/json") === nothing
        @test coap_content_format(SENML_XML) == 310
        @test content_type(SENSML_EXI) == "application/sensml-exi"
    end

    @testset "base64url" begin
        for (data, text) in [("", ""), ("f", "Zg"), ("fo", "Zm8"), ("foo", "Zm9v"),
                             ("foob", "Zm9vYg"), ("fooba", "Zm9vYmE"), ("foobar", "Zm9vYmFy")]
            @test base64url_encode(codeunits(data)) == text
            @test base64url_decode(text) == codeunits(data)
            @test SenML.base64url_length(ncodeunits(data)) == ncodeunits(text)
        end
        # RFC 8428 section 5.1.5: "aGkgCg" is "hi \n".
        @test base64url_decode("aGkgCg") == codeunits("hi \n")
        @test base64url_encode([0xfb, 0xff]) == "-_8"
        @test base64url_decode("-_8") == [0xfb, 0xff]
        for bad in ["Zg==", "+/8", "Zh", "Z"]
            @test base64url_decode(bad) === nothing
        end
    end

    @testset "numbers" begin
        for (v, text) in [(23.1, "23.1"), (20.0, "20"), (-5.0, "-5"), (1.276020076001e9, "1276020076.001"),
                          (0.1, "0.1"), (1e16, "1e16"), (1.5e-7, "1.5e-7"), (0.0, "0"), (-0.0, "-0"),
                          (floatmax(), "1.7976931348623157e308"), (1e-5, "0.00001"), (5e-324, "5e-324"),
                          (1e15, "1000000000000000"),
                          # Exact ties: Rust rounds up where Ryu picks the even digit.
                          (763219084949297.25, "763219084949297.3"),
                          (-1120781076602245.25, "-1120781076602245.3"),
                          (1855097662971146.25, "1855097662971146.3")]
            @test SenML.format_number(v) == text
            @test reinterpret(UInt64, parse(Float64, text)) == reinterpret(UInt64, v)
        end
        @test SenML.decimal_parts(120.1) == (1201, -1)
        @test SenML.decimal_parts(1.2) == (12, -1)
        @test SenML.decimal_parts(20.0) == (2, 1)
        @test SenML.decimal_parts(-0.5) == (-5, -1)
        @test SenML.decimal_parts(1.276020076001e9) == (1276020076001, -3)
        @test SenML.decimal_parts(0.0) == (0, 0)
        @test SenML.decimal_parts(763219084949297.25) == (7632190849492973, -1)
        for v in [120.1, 1e300, 5e-324, -floatmax(), 60.07965]
            @test SenML.decimal_to_float(SenML.decimal_parts(v)...) === v
        end
        @test SenML.as_exact_int(-5.0) === Int64(-5)
        @test SenML.as_exact_int(1.5) === nothing
        @test SenML.as_exact_int(-0.0) === nothing
        @test SenML.as_exact_int(1e300) === nothing
        @test SenML.as_exact_int(9.223372036854775808e18) === nothing
        @test SenML.as_exact_int(-9.223372036854775808e18) === typemin(Int64)
        @test SenML.to_float16_exact(1.5) === Float16(1.5)
        @test SenML.to_float16_exact(1.2) === nothing
        @test SenML.to_float16_exact(-0.0) === Float16(-0.0)
        @test SenML.to_float16_exact(65504.0) === Float16(65504)
        @test SenML.to_float16_exact(5.960464477539063e-8) === reinterpret(Float16, 0x0001)
        @test SenML.to_float16_exact(100_000.0) === nothing
        @test all(b -> SenML.to_float16_exact(Float64(reinterpret(Float16, b))) ===
            reinterpret(Float16, b), 0x0000:0x7bff)
        @test SenML.to_float32_exact(0.1) === nothing
        @test SenML.to_float32_exact(0.5) === 0.5f0
        # Parsing: correctly rounded, overflow to infinity, underflow to zero.
        @test SenML.parse_number("9007199254740993.000000000000000000001") == 9.007199254740994e15
        @test SenML.parse_number("4.9406564584124654e-324") == 5e-324
        @test SenML.parse_number("2.4703282292062327e-324") === 0.0
        @test SenML.parse_number("2.4703282292062328e-324") == 5e-324
        @test SenML.parse_number("1.7976931348623158e308") == floatmax()
        @test SenML.parse_number("1.7976931348623159e308") == Inf
        @test SenML.parse_number("-1e400") == -Inf
        @test SenML.parse_number("-1e-400") === -0.0
        @test SenML.parse_number("0.000001e-330") === 0.0
        @test SenML.parse_number("1" * "0"^400) == Inf
        @test SenML.parse_number("+.5") == 0.5
        @test SenML.parse_number("1.000000000000000000000000000000000000001e-99999999999999999999999") === 0.0
        @test SenML.parse_number("1.000000000000000000000000000000000000001e99999999999999999999999") == Inf
        @test SenML.decimal_to_float(2345, -2) == 23.45
        @test SenML.decimal_to_float(1, 23) == 1e23
        @test SenML.decimal_to_float(-18446744073709551616, -400) === -0.0
        @test SenML.decimal_to_float(0, 5) === 0.0
    end

    @testset "errors print" begin
        e = SenMLError(:Syntax; format = :json, offset = 3, reason = "trailing comma")
        @test sprint(showerror, e) == "SenMLError: invalid JSON at byte 3: trailing comma"
        @test occursin("record 2", sprint(showerror, SenMLError(:MissingValue; record = 2)))
    end
end
